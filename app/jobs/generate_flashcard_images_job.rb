class GenerateFlashcardImagesJob < ApplicationJob
  queue_as :default

  MAX_THREADS = 3

  def perform(deck_id, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

    deck.update_column(:image_generating, true)

    cards = deck.flashcards.order(:position)
    Rails.logger.info "[GenerateFlashcardImagesJob] Generating #{cards.size} SVG illustrations for deck #{deck_id}"

    cards.each_slice(MAX_THREADS) do |batch|
      threads = batch.map do |card|
        Thread.new do
          svg = generate_svg(card)
          card.update_column(:image_data, svg) if svg.present?
        rescue => e
          Rails.logger.warn "[GenerateFlashcardImagesJob] card #{card.id}: #{e.message}"
        end
      end
      threads.each(&:join)
    end

    if deck.learner_id.present?
      deck.learner&.deduct_credits!(5)
    else
      deck.workspace&.credit_subscription&.deduct_credits!(5)
    end
    deck.update_column(:image_generating, false)
    Rails.logger.info "[GenerateFlashcardImagesJob] Done for deck #{deck_id}"

  rescue => e
    deck&.update_column(:image_generating, false)
    Rails.logger.error "[GenerateFlashcardImagesJob] deck #{deck_id}: #{e.message}"
  end

  private

  def generate_svg(card)
    subject = (card.flashcard_deck.subject.presence || card.flashcard_deck.title).to_s.truncate(60)
    concept = card.front.to_s.truncate(80)
    meaning = card.back.to_s.truncate(120)

    svc = ClaudeService.new(model: ClaudeService::HAIKU_MODEL, timeout: 30)
    raw = svc.call(
      system_prompt: <<~SYS,
        You are an SVG illustration generator for educational flashcards.
        Return ONLY valid SVG code starting with <svg and ending with </svg>.
        No explanation, no markdown fences, no extra text. Just the raw SVG.
        Rules: viewBox="0 0 200 200", flat colorful style, no text/labels inside, max 40 elements, clean educational look.
      SYS
      user_prompt: "Draw a simple illustration for this flashcard.\nSubject: #{subject}\nConcept: #{concept}\nMeaning: #{meaning}"
    )

    extract_svg(raw)
  rescue => e
    Rails.logger.warn "[GenerateFlashcardImagesJob] SVG error for card #{card.id}: #{e.message}"
    nil
  end

  def extract_svg(raw)
    return nil if raw.blank?
    m = raw.match(/<svg[\s\S]*?<\/svg>/i)
    svg = m&.to_s
    return nil if svg.blank?
    svg.gsub(/<script[\s\S]*?<\/script>/i, "")
  end
end
