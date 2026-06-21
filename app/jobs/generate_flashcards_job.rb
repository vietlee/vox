class GenerateFlashcardsJob < ApplicationJob
  queue_as :default

  def perform(deck_id, topic, count, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

    svc = ClaudeService.for_feature("quiz_generate", timeout: 120)
    raw = svc.call(
      system_prompt: "Tạo flashcard học tập. Trả về JSON hợp lệ. Ngắn gọn, dễ nhớ.",
      user_prompt: "Tạo #{count} flashcards cho chủ đề: \"#{topic}\".\nJSON: {\"cards\":[{\"front\":\"Câu hỏi/khái niệm\",\"back\":\"Định nghĩa/đáp án ngắn gọn\"},...]}\nMặt trước: câu hỏi hoặc khái niệm. Mặt sau: đáp án/giải thích ngắn (1-3 câu).",
      max_tokens: 3000
    )
    data  = JSON.parse(raw.match(/\{.*\}/m)&.to_s || raw)
    cards = data["cards"] || []
    ActiveRecord::Base.transaction do
      cards.each_with_index { |c, i| deck.flashcards.create!(front: c["front"], back: c["back"], position: deck.flashcards.count + i) }
      deck.update!(ai_generated: true, card_count: deck.flashcards.count, ai_generating: false)
    end

    # Deduct credits
    workspace = deck.workspace
    workspace.active_subscription&.deduct_credits!(3)
  rescue => e
    deck&.update(ai_generating: false)
    Rails.logger.error "[GenerateFlashcardsJob] deck #{deck_id}: #{e.message}"
  end
end
