class GenerateLearningPathJob < ApplicationJob
  queue_as :default

  def perform(learning_path_id, prompt)
    lp = LearningPath.find_by(id: learning_path_id)
    return unless lp

    system_prompt = "Bạn là trợ lý thiết kế lộ trình học tập/đào tạo. Trả lời bằng JSON hợp lệ theo schema được yêu cầu. Không dùng từ 'giáo viên/học sinh' — dùng 'người tổ chức/người tham gia'."
    user_prompt = <<~P
      Tạo lộ trình cho: "#{lp.title}"
      Yêu cầu: #{prompt}

      Trả về JSON: {"items":[{"title":"...","item_type":"lesson","content":"...nội dung markdown...","estimated_minutes":15},{"title":"Kiểm tra...","item_type":"quiz","estimated_minutes":20},...]}
      Tạo 5-8 items, xen kẽ lesson và quiz. Content lesson phải đầy đủ, có cấu trúc markdown.
    P

    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)
    raw  = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 4000)
    data = JSON.parse(raw.match(/\{.*\}/m)&.to_s || raw)

    ActiveRecord::Base.transaction do
      data["items"].each_with_index do |item, i|
        lp.learning_path_items.create!(
          title:              item["title"],
          item_type:          item["item_type"] == "quiz" ? :quiz : :lesson,
          content:            item["content"].to_s,
          estimated_minutes:  item["estimated_minutes"].to_i.clamp(5, 120),
          position:           i
        )
      end
      lp.update!(ai_generated: true, ai_generating: false)
    end

    lp.workspace.active_subscription&.deduct_credits!(5)
  rescue => e
    lp&.update(ai_generating: false)
    Rails.logger.error "[GenerateLearningPathJob] #{learning_path_id}: #{e.message}"
  end
end
