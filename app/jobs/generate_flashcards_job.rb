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
      max_tokens: 6000
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
    deck.workspace.credit_subscription&.deduct_credits!(CreditCost[:flashcard_generate])

    deck.update_column(:ai_generating, false)
    Rails.logger.info "[GenerateFlashcardsJob] deck #{deck_id} done with #{created_cards.size} cards"

  rescue => e
    deck&.update_columns(ai_generating: false, ai_generated: false)
    Rails.logger.error "[GenerateFlashcardsJob] deck #{deck_id}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
  end

  private

  def extract_cards(raw)
    json = raw[/\{.*\}/m]
    if json
      parsed = (JSON.parse(json) rescue nil)
      return parsed["cards"] if parsed.is_a?(Hash) && parsed["cards"].is_a?(Array) && parsed["cards"].any?
    end
    # Truncated output (e.g. hit max_tokens): salvage every complete card object.
    salvage_objects(raw, "cards")
  end

  # Extract complete top-level {...} objects from a possibly-truncated "<key>":[ ... ]
  # array, tracking string/escape state so braces inside values don't skew depth.
  def salvage_objects(raw, key)
    body = raw[/"#{key}"\s*:\s*\[(.*)/m, 1] or return []
    objs = []; buf = +""; depth = 0; in_str = false; esc = false
    body.each_char do |ch|
      if in_str
        buf << ch
        if esc then esc = false
        elsif ch == "\\" then esc = true
        elsif ch == '"' then in_str = false
        end
      else
        case ch
        when '"' then in_str = true; buf << ch
        when '{' then depth += 1; buf << ch
        when '}'
          buf << ch; depth -= 1
          if depth.zero?
            obj = (JSON.parse(buf) rescue nil)
            objs << obj if obj.is_a?(Hash)
            buf = +""
          end
        else buf << ch if depth > 0
        end
      end
    end
    objs
  end
end
