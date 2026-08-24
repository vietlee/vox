class GenerateLearningPathJob < ApplicationJob
  queue_as :default

  def perform(learning_path_id, prompt)
    lp = LearningPath.find_by(id: learning_path_id)
    return unless lp

    system_prompt = "Bạn là trợ lý thiết kế lộ trình học tập/đào tạo. Trả lời bằng JSON hợp lệ theo schema được yêu cầu. Không dùng từ 'giáo viên/học sinh' — dùng 'người tổ chức/người tham gia'."
    user_prompt = <<~P
      Tạo lộ trình học tập cho: "#{lp.title}"
      Yêu cầu: #{prompt}

      Có 3 loại item:
      - "lesson": bài học lý thuyết, có trường "content" (markdown đầy đủ)
      - "quiz": bài kiểm tra trắc nghiệm, không cần content
      - "flashcard": ôn luyện thẻ ghi nhớ từ vựng/khái niệm, không cần content

      Trả về JSON:
      {"items":[
        {"title":"...","item_type":"lesson","content":"...nội dung markdown...","estimated_minutes":15},
        {"title":"Ôn luyện từ vựng...","item_type":"flashcard","estimated_minutes":10},
        {"title":"Kiểm tra...","item_type":"quiz","estimated_minutes":20}
      ]}

      Tạo 6-8 items. Xen kẽ lesson → flashcard → quiz theo từng module.
      Content lesson NGẮN GỌN (~200-300 từ, markdown có heading + gạch đầu dòng) — đủ ý, không dài dòng.
    P

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)
    raw  = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 8000)
    items = parse_items(raw)
    raise "AI không trả về item hợp lệ" if items.blank?

    ActiveRecord::Base.transaction do
      items.each_with_index do |item, i|
        type = case item["item_type"]
               when "quiz"      then :quiz
               when "flashcard" then :flashcard
               else :lesson
               end

        deck_id = nil
        if type == :flashcard
          deck = lp.workspace.flashcard_decks.create!(
            title: item["title"],
            subject: lp.subject.presence || lp.title,
            created_by: lp.created_by,
            ai_generating: true
          )
          GenerateFlashcardsJob.perform_later(deck.id, "#{item['title']} (#{lp.title})", 15, lp.created_by_id)
          deck_id = deck.id
        end

        lp.learning_path_items.create!(
          title:              item["title"],
          item_type:          type,
          content:            item["content"].to_s,
          estimated_minutes:  item["estimated_minutes"].to_i.clamp(5, 120),
          position:           i,
          flashcard_deck_id:  deck_id
        )
      end
      lp.update!(ai_generated: true, ai_generating: false)
    end

    lp.workspace.credit_subscription&.deduct_credits!(CreditCost[:learning_path_generate])
  rescue => e
    lp&.update(ai_generating: false)
    Rails.logger.error "[GenerateLearningPathJob] #{learning_path_id}: #{e.message}"
  end

  private

  # Parse the AI's item list. Falls back to salvaging every complete {...} object
  # inside the "items" array when the JSON is truncated (e.g. hit max_tokens),
  # so a cut-off response still yields the items it managed to produce.
  def parse_items(raw)
    json = raw[/\{.*\}/m] || raw
    parsed = JSON.parse(json)
    arr = parsed["items"]
    return arr if arr.is_a?(Array) && arr.any?
    []
  rescue JSON::ParserError
    salvage_items(raw)
  end

  # Extract complete top-level objects from a (possibly truncated) items array,
  # tracking string/escape state so braces inside content don't confuse depth.
  def salvage_items(raw)
    body = raw[/"items"\s*:\s*\[(.*)/m, 1] or return []
    objs = []
    buf = +""; depth = 0; in_str = false; esc = false
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
          buf << ch
          depth -= 1
          if depth == 0
            obj = (JSON.parse(buf) rescue nil)
            objs << obj if obj.is_a?(Hash)
            buf = +""
          end
        else
          buf << ch if depth > 0
        end
      end
    end
    objs
  end
end
