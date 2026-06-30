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
        - visual_concept: mô tả ngắn gọn bằng tiếng Anh về khái niệm cần minh họa bằng hình vẽ (1-2 câu)

        Trả về JSON theo đúng format này, không có text nào khác:
        {"cards":[{"front":"...","back":"...","visual_concept":"..."}]}
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
        created_cards << { card: card, concept: c["visual_concept"].to_s.strip }
      end
      deck.update!(ai_generated: true, card_count: created_cards.size)
    end

    # Deduct credits only after successful creation
    deck.workspace.credit_subscription&.deduct_credits!(3)

    # Step 2: Generate SVG illustrations for each card (sequential, silent on error)
    svg_svc = ClaudeService.new(model: ClaudeService::SONNET_MODEL, timeout: 120)
    created_cards.each_with_index do |item, idx|
      next if item[:concept].blank?
      Rails.logger.info "[GenerateFlashcardsJob] SVG #{idx + 1}/#{created_cards.size} for card #{item[:card].id}: #{item[:card].front}"
      svg = generate_svg(svg_svc, item[:card].front, item[:card].back, item[:concept])
      if svg.present?
        item[:card].update_column(:image_data, svg)
        Rails.logger.info "[GenerateFlashcardsJob] SVG #{idx + 1} saved (#{svg.length} chars)"
      else
        Rails.logger.warn "[GenerateFlashcardsJob] SVG #{idx + 1} empty/nil"
      end
    rescue => e
      Rails.logger.warn "[GenerateFlashcardsJob] SVG #{idx + 1} failed: #{e.message}"
    end

    # Mark done only after all SVGs are generated
    Rails.logger.info "[GenerateFlashcardsJob] All done, marking deck #{deck_id} not generating"
    deck.update_column(:ai_generating, false)

  rescue => e
    deck&.update(ai_generating: false)
    Rails.logger.error "[GenerateFlashcardsJob] deck #{deck_id}: #{e.message}"
  end

  private

  def generate_svg(svc, front, back, concept)
    prompt = <<~PROMPT
      Draw a beautiful, detailed SVG illustration for a flashcard.

      Card word/topic: "#{front}"
      Back side (meaning/explanation): "#{back}"
      What to illustrate: "#{concept}"

      STYLE GUIDE — follow exactly:
      - viewBox="0 0 400 300", no width/height attributes
      - Cute, friendly, rounded illustration style — think modern emoji or children's book art
      - Rich colors: use gradients (linearGradient / radialGradient) for depth and vibrancy
      - Draw the ACTUAL OBJECT/ANIMAL/THING — not an icon or symbol. If it's a cat, draw a cat with body, face, ears, tail. If it's a computer, draw a monitor with screen details.
      - Use <circle>, <ellipse>, <path>, <rect> with rounded corners to build realistic-looking characters/objects
      - Add shading: a slightly darker fill on shadow sides, a lighter highlight circle for shine
      - Background: a soft 2-color gradient rectangle filling the whole canvas (pick colors that suit the topic — sky blue for animals, warm yellow for food, etc.)
      - Foreground: the main illustration centered, large (filling ~70% of canvas height)
      - NO text labels inside the SVG
      - Make it look polished and charming — something a student would enjoy seeing

      IMPORTANT: Keep the SVG compact — use short attribute values, avoid unnecessary whitespace and comments. The entire SVG must be completable within token limits.

      Return ONLY the SVG code starting with <svg and ending with </svg>. No explanation, no markdown, no comments inside SVG.
    PROMPT

    raw = svc.call(
      system_prompt: "You are an expert SVG artist specializing in cute, detailed educational illustrations. You draw recognizable objects, animals, and scenes using SVG shapes and gradients. Return only valid SVG code with no explanation.",
      user_prompt: prompt,
      max_tokens: 6000
    )

    # Extract SVG from response — greedy match to capture full nested SVG
    svg = raw.match(/<svg[\s\S]*<\/svg>/i)&.to_s
    return nil if svg.blank?

    # Basic sanitization: remove script tags and any stray </script> closing tags
    svg.gsub(/<script[\s\S]*?<\/script>/i, '')
       .gsub(/<\/script>/i, '')
       .gsub(/\son\w+="[^"]*"/i, '')
  end

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
