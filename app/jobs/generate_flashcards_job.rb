require "net/http"
require "uri"

class GenerateFlashcardsJob < ApplicationJob
  queue_as :default

  def perform(deck_id, topic, count, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

    svc = ClaudeService.for_feature("quiz_generate", timeout: 120)
    raw = svc.call(
      system_prompt: "Tạo flashcard học tập. Trả về JSON hợp lệ. Ngắn gọn, dễ nhớ.",
      user_prompt: <<~PROMPT,
        Tạo #{count} flashcards cho chủ đề: "#{topic}".
        JSON: {"cards":[{"front":"Câu hỏi/khái niệm","back":"Định nghĩa/đáp án ngắn gọn","image_keyword":"1-3 english words for image search (noun/concept, no verbs)"},...]}
        Mặt trước: câu hỏi hoặc khái niệm. Mặt sau: đáp án/giải thích ngắn (1-3 câu).
        image_keyword: từ khóa tiếng Anh ngắn gọn để tìm ảnh minh họa (ví dụ: "photosynthesis", "solar system", "human heart").
      PROMPT
      max_tokens: 3500
    )

    data  = JSON.parse(raw.match(/\{.*\}/m)&.to_s || raw)
    cards = data["cards"] || []

    created_cards = []
    ActiveRecord::Base.transaction do
      cards.each_with_index do |c, i|
        card = deck.flashcards.create!(front: c["front"], back: c["back"], position: deck.flashcards.count + i)
        created_cards << { card: card, keyword: c["image_keyword"].to_s.strip }
      end
      deck.update!(ai_generated: true, card_count: deck.flashcards.count, ai_generating: false)
    end

    # Deduct credits
    deck.workspace.active_subscription&.deduct_credits!(3)

    # Fetch images in background (non-blocking — failures are silent)
    created_cards.each do |item|
      next if item[:keyword].blank?
      image_url = fetch_image_url(item[:keyword])
      item[:card].update_column(:image_data, image_url) if image_url
    end

  rescue => e
    deck&.update(ai_generating: false)
    Rails.logger.error "[GenerateFlashcardsJob] deck #{deck_id}: #{e.message}"
  end

  private

  # Returns a direct image URL (stored in image_data column).
  # Tries Wikipedia thumbnail first, falls back to LoremFlickr.
  def fetch_image_url(keyword)
    wikipedia_image(keyword) || loremflickr_url(keyword)
  rescue => e
    Rails.logger.warn "[GenerateFlashcardsJob] image fetch failed for '#{keyword}': #{e.message}"
    nil
  end

  def wikipedia_image(keyword)
    slug = URI.encode_www_form_component(keyword.gsub(/\s+/, "_"))
    uri  = URI("https://en.wikipedia.org/api/rest_v1/page/summary/#{slug}")
    res  = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 5) do |http|
      http.get(uri.request_uri, "User-Agent" => "VOX-Flashcard/1.0")
    end
    return nil unless res.is_a?(Net::HTTPSuccess)
    data  = JSON.parse(res.body)
    thumb = data.dig("thumbnail", "source")
    # Prefer larger image (originalimage) if available and not too big
    orig  = data.dig("originalimage", "source")
    w     = data.dig("originalimage", "width").to_i
    (orig && w > 0 && w <= 1200) ? orig : thumb
  end

  # LoremFlickr returns a redirect to a real Flickr CC image.
  # We follow the redirect once to get a stable URL.
  def loremflickr_url(keyword)
    encoded = URI.encode_www_form_component(keyword.gsub(/\s+/, ","))
    uri = URI("https://loremflickr.com/600/400/#{encoded}")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: false, open_timeout: 4, read_timeout: 5) do |http|
      http.get(uri.request_uri, "User-Agent" => "VOX-Flashcard/1.0")
    end
    # Follow one redirect
    if res.is_a?(Net::HTTPRedirection) && res["location"]
      return res["location"]
    end
    nil
  end
end
