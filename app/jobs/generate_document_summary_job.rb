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

  def extract_and_summarize(summary)
    filename = summary.source_filename.to_s.downcase
    data     = summary.source_file.download
    ext      = File.extname(filename).downcase

    case ext
    when ".pdf"
      text = extract_pdf(data)
      summarize_text(summary, text)
    when ".docx"
      text = extract_docx(data)
      summarize_text(summary, text)
    when ".doc"
      text = extract_doc(data)
      summarize_text(summary, text)
    when ".txt", ".csv"
      text = data.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).scrub
      summarize_text(summary, text)
    when ".xlsx", ".xls"
      text = extract_excel(data, ext)
      summarize_text(summary, text)
    when ".pptx"
      text = extract_pptx(data)
      summarize_text(summary, text)
    when ".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"
      summarize_image(summary, data, summary.source_file.content_type)
    else
      # Try to detect from content_type
      ct = summary.source_file.content_type.to_s
      if ct.include?("pdf")
        summarize_text(summary, extract_pdf(data))
      elsif ct.start_with?("image/")
        summarize_image(summary, data, ct)
      else
        text = data.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).scrub
        summarize_text(summary, text)
      end
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

  MAX_IMAGE_DIMENSION = 7000

  def resize_image_for_claude(data)
    require "mini_magick"
    img = MiniMagick::Image.read(data)
    if img.width > MAX_IMAGE_DIMENSION || img.height > MAX_IMAGE_DIMENSION
      img.resize "#{MAX_IMAGE_DIMENSION}x#{MAX_IMAGE_DIMENSION}>"
      img.to_blob
    else
      data
    end
  rescue => e
    Rails.logger.warn "[GenerateDocumentSummaryJob] resize failed: #{e.message}"
    data
  end

  def summarize_image(summary, data, mime_type)
    safe_data = resize_image_for_claude(data)
    svc = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    messages = [{
      role: "user",
      content: [
        { type: "image", source: { type: "base64", media_type: mime_type, data: Base64.strict_encode64(safe_data) } },
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

    summary.workspace.credit_subscription&.deduct_credits!(2)
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

  # ── File extractors ───────────────────────────────────────────────────────────

  def extract_pdf(data)
    require "open3"
    tmp = Tempfile.new(["ds_upload", ".pdf"])
    begin
      tmp.binmode; tmp.write(data); tmp.flush

      # 1. pdftotext (poppler-utils) — handles compressed/encrypted PDFs
      stdout, _e, status = Open3.capture3("pdftotext", "-enc", "UTF-8", tmp.path, "-")
      return stdout.strip if status.success? && stdout.strip.present?

      # 2. pdf-reader gem (pure Ruby fallback)
      begin
        require "pdf-reader"
        reader = PDF::Reader.new(StringIO.new(data))
        text   = reader.pages.map(&:text).join("\n").strip
        return text if text.present?
      rescue => e
        Rails.logger.warn "[GenerateDocumentSummaryJob] pdf-reader: #{e.message}"
      end

      nil
    ensure
      tmp.close!
    end
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
         .gsub(/\n /, "\n")
         .strip
    end
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_docx: #{e.message}"
    nil
  end

  def extract_doc(data)
    require "open3"
    tmp = Tempfile.new(["ds_upload", ".doc"])
    tmp.binmode; tmp.write(data); tmp.flush
    out, _e, st = Open3.capture3("antiword", tmp.path)
    tmp.close!
    return out.strip if st.success? && out.strip.present?
    # Fallback: extract printable ASCII runs
    data.force_encoding("binary").scan(/[\x20-\x7E\n\r]{4,}/).join(" ").gsub(/\s+/, " ").strip.presence
  rescue
    nil
  end

  def extract_excel(data, ext)
    require "zip"
    # XLSX is a ZIP — extract sharedStrings.xml + sheet XMLs
    io = StringIO.new(data)
    texts = []
    Zip::File.open_buffer(io) do |zip|
      # Shared strings (cell text values)
      shared = []
      if (ss = zip.find_entry("xl/sharedStrings.xml"))
        xml = ss.get_input_stream.read.force_encoding("UTF-8")
        shared = xml.scan(/<t[^>]*>([^<]+)<\/t>/).flatten
      end
      texts.concat(shared)

      # Sheet names from workbook
      if (wb = zip.find_entry("xl/workbook.xml"))
        xml = wb.get_input_stream.read.force_encoding("UTF-8")
        texts += xml.scan(/name="([^"]+)"/).flatten
      end
    end
    texts.uniq.reject(&:empty?).join("\n").truncate(15000)
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_excel: #{e.message}"
    nil
  end

  def extract_pptx(data)
    require "zip"
    io = StringIO.new(data)
    slides_text = []
    Zip::File.open_buffer(io) do |zip|
      slide_entries = zip.select { |e| e.name.match?(%r{ppt/slides/slide\d+\.xml}) }
                        .sort_by { |e| e.name[/\d+/].to_i }
      slide_entries.each do |entry|
        xml = entry.get_input_stream.read.force_encoding("UTF-8")
        # Extract <a:t> text runs
        texts = xml.scan(/<a:t[^>]*>([^<]+)<\/a:t>/).flatten.map(&:strip).reject(&:empty?)
        slides_text << texts.join(" ") if texts.any?
      end
    end
    slides_text.each_with_index.map { |t, i| "Slide #{i+1}: #{t}" }.join("\n").truncate(15000)
  rescue => e
    Rails.logger.error "[GenerateDocumentSummaryJob] extract_pptx: #{e.message}"
    nil
  end
end
