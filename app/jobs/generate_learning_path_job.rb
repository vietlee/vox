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

      Tạo 6-9 items. Xen kẽ lesson → flashcard → quiz theo từng module. Content lesson phải đầy đủ, có cấu trúc markdown.
    P

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)
    raw  = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 4000)
    data = JSON.parse(raw.match(/\{.*\}/m)&.to_s || raw)

    ActiveRecord::Base.transaction do
      data["items"].each_with_index do |item, i|
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

    lp.workspace.credit_subscription&.deduct_credits!(5)
  rescue => e
    lp&.update(ai_generating: false)
    Rails.logger.error "[GenerateLearningPathJob] #{learning_path_id}: #{e.message}"
  end
end
