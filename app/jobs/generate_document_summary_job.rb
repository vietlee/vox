class GenerateDocumentSummaryJob < ApplicationJob
  queue_as :default

  def perform(summary_id)
    summary = DocumentSummary.find_by(id: summary_id)
    return unless summary&.pending?

    if summary.source_text.present?
      # Plain text input — summarize directly
      summarize_text(summary, summary.source_text)
    elsif summary.source_file.attached?
      extract_and_summarize(summary)
    else
      summary.update!(status: :failed)
    end
  rescue => e
    summary&.update(status: :failed)
    Rails.logger.error "[GenerateDocumentSummaryJob] #{summary_id}: #{e.message}"
  end

  private

  # File extraction (PDF/DOCX/images/…) is centralised in FileContentExtractor.
  # We only dispatch on whether it yielded text or an image and summarize.
  def extract_and_summarize(summary)
    result = FileContentExtractor.extract(
      data:         summary.source_file.download,
      filename:     summary.source_filename.to_s,
      content_type: summary.source_file.content_type
    )

    if result[:kind] == :image
      summarize_image(summary, result[:data], result[:mime])
    else
      summarize_text(summary, result[:text])
    end
  end

  # ── Text-based summarization ─────────────────────────────────────────────────

  def summarize_text(summary, text)
    if text.blank?
      summary.update!(status: :failed)
      Rails.logger.error "[GenerateDocumentSummaryJob] #{summary.id}: empty text after extraction"
      return
    end

    svc    = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    result = svc.call(
      system_prompt: "Bạn là trợ lý tóm tắt tài liệu chuyên nghiệp. Trả về JSON hợp lệ, không có markdown.",
      user_prompt:   build_text_prompt(text),
      max_tokens:    2000
    )

    save_result(summary, result)
  end

  # ── Image-based summarization (AI vision) ────────────────────────────────────

  def summarize_image(summary, data, mime_type)
    svc = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    messages = [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: mime_type, data: Base64.strict_encode64(data) } },
        { type: "text", text: build_image_prompt }
      ]
    }]
    result = svc.call(system_prompt: "Bạn là trợ lý tóm tắt tài liệu chuyên nghiệp. Trả về JSON hợp lệ, không có markdown.",
                      messages: messages, max_tokens: 2000)
    save_result(summary, result)
  end

  # ── Save AI result ────────────────────────────────────────────────────────────

  def save_result(summary, result)
    cleaned  = result.gsub(/```(?:json)?\s*/i, '').gsub(/```/, '').strip
    json_str = cleaned.match(/\{.*\}/m)&.to_s || cleaned
    data     = JSON.parse(json_str)

    summary.workspace.credit_subscription&.deduct_credits!(CreditCost[:document_summary])
    summary.update!(
      summary:    data["summary"],
      key_points: data["key_points"].to_json,
      title:      summary.title.presence || data["title_suggestion"],
      status:     :done
    )
  end

  # ── Prompts ───────────────────────────────────────────────────────────────────

  def build_text_prompt(text)
    "Tóm tắt tài liệu sau.\n\nTài liệu:\n#{text.truncate(15000)}\n\n" \
    "Chỉ trả về JSON theo đúng format (không thêm gì khác):\n" \
    '{"summary":"tóm tắt tổng quan 3-5 câu","key_points":["điểm chính 1","điểm chính 2","điểm chính 3"],"title_suggestion":"tiêu đề gợi ý"}'
  end

  def build_image_prompt
    "Hãy đọc và tóm tắt nội dung trong ảnh/tài liệu này.\n\n" \
    "Chỉ trả về JSON theo đúng format (không thêm gì khác):\n" \
    '{"summary":"tóm tắt tổng quan 3-5 câu","key_points":["điểm chính 1","điểm chính 2","điểm chính 3"],"title_suggestion":"tiêu đề gợi ý"}'
  end
end
