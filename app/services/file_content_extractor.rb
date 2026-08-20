# Reads an uploaded file (image or document) into a form usable by Claude.
#
# `extract` returns either:
#   { kind: :image, data: <resized blob>, mime: <mime type> }  — for images
#   { kind: :text,  text: <extracted text> }                   — for documents
#
# `to_claude_block` wraps that into a Claude message content block, so callers
# can drop the result straight into a multimodal `content:` array.
#
# The document extractors (PDF/DOCX/DOC/XLSX/PPTX) and the image resize logic
# were originally private to GenerateDocumentSummaryJob; centralised here so the
# AI Survey Builder can reuse the exact same behaviour.
class FileContentExtractor
  IMAGE_EXTS = %w[png jpg jpeg webp gif bmp].freeze
  MAX_IMAGE_DIMENSION = 7000
  MAX_TEXT_CHARS = 15_000

  def self.extract(data:, filename:, content_type: nil)
    new(data: data, filename: filename, content_type: content_type).extract
  end

  def self.to_claude_block(data:, filename:, content_type: nil)
    new(data: data, filename: filename, content_type: content_type).to_claude_block
  end

  def initialize(data:, filename:, content_type: nil)
    @data         = data
    @filename     = filename.to_s
    @content_type = content_type.to_s
    @ext          = File.extname(@filename).delete(".").downcase
  end

  def extract
    if image?
      { kind: :image, data: resize_image_for_claude(@data), mime: image_mime }
    else
      { kind: :text, text: extract_text }
    end
  end

  # Returns a Claude content block, or nil when nothing could be extracted.
  def to_claude_block
    result = extract
    if result[:kind] == :image
      {
        type: "image",
        source: { type: "base64", media_type: result[:mime], data: Base64.strict_encode64(result[:data]) }
      }
    else
      text = result[:text].to_s.strip
      return nil if text.blank?
      label = @filename.presence || "tài liệu đính kèm"
      { type: "text", text: "Nội dung file «#{label}»:\n#{text.truncate(MAX_TEXT_CHARS)}" }
    end
  end

  private

  def image?
    return true if @ext.in?(IMAGE_EXTS)
    @ext.blank? && @content_type.start_with?("image/")
  end

  def image_mime
    return @content_type if @content_type.start_with?("image/")
    case @ext
    when "png"        then "image/png"
    when "webp"       then "image/webp"
    when "gif"        then "image/gif"
    when "bmp"        then "image/bmp"
    else "image/jpeg"
    end
  end

  def extract_text
    case @ext
    when "pdf"          then extract_pdf(@data)
    when "docx"         then extract_docx(@data)
    when "doc"          then extract_doc(@data)
    when "txt", "csv"   then @data.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).scrub
    when "xlsx", "xls"  then extract_excel(@data, @ext)
    when "pptx"         then extract_pptx(@data)
    else
      # Detect from content_type when the extension is unknown
      if @content_type.include?("pdf")
        extract_pdf(@data)
      else
        @data.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace).scrub
      end
    end
  end

  # ── Image resize for Claude vision ────────────────────────────────────────────

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
    Rails.logger.warn "[FileContentExtractor] resize failed: #{e.message}"
    data
  end

  # ── Document extractors ───────────────────────────────────────────────────────

  def extract_pdf(data)
    require "open3"
    tmp = Tempfile.new(["fce_upload", ".pdf"])
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
        Rails.logger.warn "[FileContentExtractor] pdf-reader: #{e.message}"
      end

      nil
    ensure
      tmp.close!
    end
  rescue => e
    Rails.logger.error "[FileContentExtractor] extract_pdf: #{e.message}"
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
    Rails.logger.error "[FileContentExtractor] extract_docx: #{e.message}"
    nil
  end

  def extract_doc(data)
    require "open3"
    tmp = Tempfile.new(["fce_upload", ".doc"])
    tmp.binmode; tmp.write(data); tmp.flush
    out, _e, st = Open3.capture3("antiword", tmp.path)
    tmp.close!
    return out.strip if st.success? && out.strip.present?
    # Fallback: extract printable ASCII runs
    data.dup.force_encoding("binary").scan(/[\x20-\x7E\n\r]{4,}/).join(" ").gsub(/\s+/, " ").strip.presence
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
    texts.uniq.reject(&:empty?).join("\n").truncate(MAX_TEXT_CHARS)
  rescue => e
    Rails.logger.error "[FileContentExtractor] extract_excel: #{e.message}"
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
    slides_text.each_with_index.map { |t, i| "Slide #{i + 1}: #{t}" }.join("\n").truncate(MAX_TEXT_CHARS)
  rescue => e
    Rails.logger.error "[FileContentExtractor] extract_pptx: #{e.message}"
    nil
  end
end
