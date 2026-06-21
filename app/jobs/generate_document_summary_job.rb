class GenerateDocumentSummaryJob < ApplicationJob
  queue_as :default

  def perform(summary_id)
    summary = DocumentSummary.find_by(id: summary_id)
    return unless summary&.pending?

    text = summary.source_text.presence
    if text.blank? && summary.source_file.attached?
      text = extract_file(summary)
    end

    if text.blank?
      summary.update!(status: :failed)
      Rails.logger.error "[GenerateDocumentSummaryJob] #{summary_id}: could not extract text from file"
      return
    end

    svc = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    result = svc.call(
      system_prompt: "Bạn là trợ lý tóm tắt tài liệu chuyên nghiệp. Trả về JSON hợp lệ, không có markdown.",
      user_prompt: "Tóm tắt tài liệu sau.\n\nTài liệu:\n#{text.truncate(15000)}\n\nChỉ trả về JSON theo đúng format (không thêm gì khác):\n{\"summary\":\"tóm tắt tổng quan 3-5 câu\",\"key_points\":[\"điểm chính 1\",\"điểm chính 2\"],\"title_suggestion\":\"tiêu đề gợi ý\"}",
      max_tokens: 2000
    )

    cleaned = result.gsub(/```(?:json)?\s*/i, '').gsub(/```/, '').strip
    json_str = cleaned.match(/\{.*\}/m)&.to_s || cleaned
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

  private

  def extract_file(summary)
    filename = summary.source_filename.to_s.downcase
    data = summary.source_file.download

    if filename.end_with?(".pdf") || summary.source_file.content_type == "application/pdf"
      extract_pdf(data)
    elsif filename.end_with?(".docx") || filename.end_with?(".doc")
      extract_docx(data)
    else
      # Plain text / TXT
      data.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).scrub
    end
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_file error: #{e.message}"
    nil
  end

  def extract_pdf(data)
    require "open3"
    tmp = Tempfile.new(["doc_summary", ".pdf"])
    tmp.binmode
    tmp.write(data)
    tmp.flush

    # 1. pdftotext (poppler-utils) — handles encrypted/compressed PDFs
    stdout, _stderr, status = Open3.capture3("pdftotext", "-enc", "UTF-8", tmp.path, "-")
    if status.success? && stdout.strip.present?
      tmp.close!
      return stdout.strip
    end

    # 2. pdf-reader gem (pure Ruby fallback)
    begin
      require "pdf-reader"
      reader = PDF::Reader.new(StringIO.new(data))
      text = reader.pages.map(&:text).join("\n").strip
      tmp.close!
      return text if text.present?
    rescue => e
      Rails.logger.warn "[GenerateDocumentSummaryJob] pdf-reader failed: #{e.message}"
    end

    tmp.close!
    nil
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_pdf: #{e.message}"
    nil
  end

  def extract_docx(data)
    require "zip"
    io = StringIO.new(data)
    Zip::File.open_buffer(io) do |zip|
      entry = zip.find_entry("word/document.xml")
      return nil unless entry
      xml = entry.get_input_stream.read.force_encoding("UTF-8")
      xml.gsub(/<w:p[ >]/, "\n<w:p>")
         .gsub(/<[^>]+>/, " ")
         .gsub(/\s{2,}/, " ")
         .strip
    end
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_docx: #{e.message}"
    nil
  end
end
