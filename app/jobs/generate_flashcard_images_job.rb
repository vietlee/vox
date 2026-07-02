class GenerateFlashcardImagesJob < ApplicationJob
  queue_as :default

  DALLE_API_URL = "https://api.openai.com/v1/images/generations"
  MAX_THREADS   = 3

  def perform(deck_id, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

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
    prompt = "Educational flashcard illustration for: #{card.front}. " \
             "Clean, simple, colorful flat illustration style. No text in image."

    # Try dall-e-3 first, fall back to dall-e-2 if unavailable
    ["dall-e-3", "dall-e-2"].each do |model|
      result = call_dalle(prompt, model, card.id, api_key)
      return result if result
    end
    nil
  end

  def call_dalle(prompt, model, card_id, api_key)
    body = { model: model, prompt: prompt, n: 1,
             size: model == "dall-e-3" ? "1024x1024" : "512x512" }

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
      data.dig("data", 0, "url")
    else
      msg = data.dig("error", "message").to_s
      Rails.logger.warn "[GenerateFlashcardImagesJob] #{model} error for card #{card_id}: #{msg}"
      nil
    end
  rescue => e
    Rails.logger.warn "[GenerateFlashcardImagesJob] HTTP error (#{model}) for card #{card_id}: #{e.message}"
    nil
  end
end
