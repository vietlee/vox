class GenerateFlashcardSvgsJob < ApplicationJob
  queue_as :default

  MAX_THREADS = 5
  UNSPLASH_ACCESS_KEY = ENV["UNSPLASH_ACCESS_KEY"]

  # card_pairs: [[card_id, visual_concept], ...]
  def perform(card_pairs)
    return if card_pairs.blank?
    return unless UNSPLASH_ACCESS_KEY.present?

    Rails.logger.info "[GenerateFlashcardSvgsJob] Fetching #{card_pairs.size} Unsplash images"

    card_pairs.each_slice(MAX_THREADS) do |batch|
      threads = batch.map do |(card_id, concept)|
        Thread.new do
          card = Flashcard.find_by(id: card_id)
          next unless card && concept.present?

          url = fetch_unsplash_url(concept)
          if url.present?
            card.update_column(:image_data, url)
            Rails.logger.info "[GenerateFlashcardSvgsJob] Image set for card #{card_id}"
          else
            Rails.logger.warn "[GenerateFlashcardSvgsJob] No image found for card #{card_id}: #{concept}"
          end
        rescue => e
          Rails.logger.warn "[GenerateFlashcardSvgsJob] Failed for card #{card_id}: #{e.message}"
        end
      end
      threads.each(&:join)
    end

    Rails.logger.info "[GenerateFlashcardSvgsJob] Done"
  end

  private

  def fetch_unsplash_url(concept)
    # Use first 5 words of concept as query for better relevance
    query = concept.split.first(5).join(" ")
    uri = URI("https://api.unsplash.com/photos/random")
    uri.query = URI.encode_www_form(query: query, orientation: "landscape", content_filter: "high")

    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Client-ID #{UNSPLASH_ACCESS_KEY}"
    req["Accept-Version"] = "v1"

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) do |http|
      http.request(req)
    end

    return nil unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    # Use "small" size (400px wide) — good balance of quality and load speed
    data.dig("urls", "small")
  rescue => e
    Rails.logger.warn "[GenerateFlashcardSvgsJob] Unsplash API error: #{e.message}"
    nil
  end
end
