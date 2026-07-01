class GenerateFlashcardsJob < ApplicationJob
  queue_as :default

  def perform(deck_id, topic, count, user_id)
    deck = FlashcardDeck.find_by(id: deck_id)
    return unless deck

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    # Step 1: Generate card content
    raw = svc.call(
      system_prompt: "Bạn là chuyên gia tạo flashcard học tập. Chỉ trả về JSON hợp lệ, không giải thích thêm.",
      user_prompt: <<~PROMPT,
        Tạo #{count} flashcards cho chủ đề: "#{topic}".

        Yêu cầu:
        - Mặt trước (front): câu hỏi hoặc khái niệm cốt lõi, ngắn gọn (tối đa 15 từ). Nếu là từ/cụm từ tiếng Việt, PHẢI có ít nhất 2 âm tiết — không dùng từ đơn âm tiết (ví dụ: thay "gối" bằng "cái gối", "mắt" bằng "đôi mắt", "chân" bằng "bàn chân"). Nếu là từ vựng nước ngoài thì giữ nguyên.
        - Mặt sau (back): đáp án/giải thích súc tích (1-3 câu, tối đa 50 từ)

        Trả về JSON theo đúng format này, không có text nào khác:
        {"cards":[{"front":"...","back":"..."}]}
      PROMPT
      max_tokens: 3500
    )

    cards_data = extract_cards(raw)
    raise "AI không trả về dữ liệu hợp lệ" if cards_data.empty?

    created_cards = []
    ActiveRecord::Base.transaction do
      cards_data.each_with_index do |c, i|
        next if c["front"].blank? || c["back"].blank?
        card = deck.flashcards.create!(
          front:    c["front"].to_s.gsub("/", ", ").truncate(200),
          back:     c["back"].to_s.gsub("/", ", ").truncate(500),
          position: i
        )
        created_cards << card.id
      end
      deck.update!(ai_generated: true, card_count: created_cards.size)
    end

    # Deduct credits after successful card creation
    deck.workspace.credit_subscription&.deduct_credits!(3)

    deck.update_column(:ai_generating, false)
    Rails.logger.info "[GenerateFlashcardsJob] deck #{deck_id} done with #{created_cards.size} cards"

  rescue => e
    deck&.update_columns(ai_generating: false, ai_generated: false)
    Rails.logger.error "[GenerateFlashcardsJob] deck #{deck_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
  end

  private

  def extract_cards(raw)
    raw.scan(/\{[^{}]*"cards"\s*:\s*\[[\s\S]*?\]\s*\}/m).each do |candidate|
      parsed = JSON.parse(candidate)
      return parsed["cards"] if parsed["cards"].is_a?(Array)
    rescue JSON::ParserError
      next
    end

    parsed = JSON.parse(raw)
    return parsed["cards"] if parsed["cards"].is_a?(Array)
    []
  rescue JSON::ParserError
    begin
      match = raw.match(/\{.+\}/m)&.to_s
      return [] if match.nil?
      parsed = JSON.parse(match)
      parsed["cards"].is_a?(Array) ? parsed["cards"] : []
    rescue
      []
    end
  end
end
