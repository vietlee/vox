class GenerateFlashcardImagesJob < ApplicationJob
  queue_as :default

  DALLE_API_URL = "https://api.openai.com/v1/images/generations"
  MAX_THREADS   = 3

  def perform(deck_id, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

    # Re-set flag on retries (first attempt may have cleared it via rescue)
    deck.update_column(:image_generating, true)

    api_key = ENV["OPENAI_API_KEY"]
    unless api_key.present?
      Rails.logger.error "[GenerateFlashcardImagesJob] OPENAI_API_KEY not set"
      deck.update_column(:image_generating, false)
      return
    end

    cards = deck.flashcards.order(:position)
    Rails.logger.info "[GenerateFlashcardImagesJob] Generating #{cards.size} images for deck #{deck_id}"

    cards.each_slice(MAX_THREADS) do |batch|
      threads = batch.map do |card|
        Thread.new do
          url = generate_image(card, api_key)
          card.update_column(:image_data, url) if url.present?
        rescue => e
          Rails.logger.warn "[GenerateFlashcardImagesJob] card #{card.id}: #{e.message}"
        end
      end
      threads.each(&:join)
    end

    deck.workspace.credit_subscription&.deduct_credits!(5)
    deck.update_column(:image_generating, false)
    Rails.logger.info "[GenerateFlashcardImagesJob] Done for deck #{deck_id}"

  rescue => e
    deck&.update_column(:image_generating, false)
    Rails.logger.error "[GenerateFlashcardImagesJob] deck #{deck_id}: #{e.message}"
  end

  private

  def generate_image(card, api_key)
    deck_context = card.flashcard_deck.subject.presence || card.flashcard_deck.title
    # Use back content to disambiguate (e.g. "Mouse" + "A pointing device" → computer mouse, not animal)
    explanation = card.back.to_s.truncate(120)
    prompt = "Flat illustration for an educational flashcard. " \
             "Topic/subject: #{deck_context}. " \
             "Concept: #{card.front}. " \
             "Definition/explanation: #{explanation}. " \
             "Illustrate exactly what the definition describes. " \
             "Clean, simple, colorful vector illustration style. No text, no labels, no words in image."

    call_dalle(prompt, card.id, api_key)
  end

  def call_dalle(prompt, card_id, api_key)
    body = { model: "gpt-image-1.5", prompt: prompt, n: 1, size: "1024x1024", output_format: "webp" }

    uri = URI(DALLE_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 60

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = "Bearer #{api_key}"
    req.body = body.to_json

    res  = http.request(req)
    data = JSON.parse(res.body)

    if res.is_a?(Net::HTTPSuccess)
      b64 = data.dig("data", 0, "b64_json")
      b64.present? ? "data:image/webp;base64,#{b64}" : nil
    else
      msg = data.dig("error", "message").to_s
      Rails.logger.warn "[GenerateFlashcardImagesJob] gpt-image-1 error for card #{card_id}: #{msg}"
      nil
    end
  rescue => e
    Rails.logger.warn "[GenerateFlashcardImagesJob] HTTP error for card #{card_id}: #{e.message}"
    nil
  end
end
