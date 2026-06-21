class GenerateDocumentSummaryJob < ApplicationJob
  queue_as :default

  def perform(summary_id)
    summary = DocumentSummary.find_by(id: summary_id)
    return unless summary&.pending?

    text = summary.source_text.presence
    if text.blank? && summary.source_file.attached?
      text = summary.source_file.download.force_encoding("UTF-8").scrub
    end
    return summary.update!(status: :failed) if text.blank?

    svc = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    result = svc.call(
      system_prompt: "Bạn là trợ lý tóm tắt tài liệu chuyên nghiệp. Trả về JSON hợp lệ.",
      user_prompt: "Tóm tắt tài liệu sau.\n\nTài liệu:\n#{text.to_s.truncate(15000)}\n\nJSON: {\"summary\":\"tóm tắt tổng quan 3-5 câu\",\"key_points\":[\"điểm chính 1\",...],\"title_suggestion\":\"tiêu đề gợi ý nếu không có\"}",
      max_tokens: 2000
    )
    json_str = result.match(/\{.*\}/m)&.to_s || result
    data = JSON.parse(json_str)
    summary.workspace.active_subscription&.deduct_credits!(2)
    summary.update!(
      summary:    data["summary"],
      key_points: data["key_points"].to_json,
      title:      summary.title.presence || data["title_suggestion"],
      status:     :done
    )
  rescue => e
    summary&.update(status: :failed)
    Rails.logger.error "[GenerateDocumentSummaryJob] #{summary_id}: #{e.message}"
  end
end
