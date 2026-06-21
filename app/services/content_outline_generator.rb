class ContentOutlineGenerator
  PPTX_SCRIPT = Rails.root.join("scripts", "generate_pptx.py").to_s

  def self.call(outline)
    new(outline).call
  end

  def initialize(outline)
    @outline = outline
  end

  def call
    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    if @outline.output_type == "slide"
      result = svc.call(system_prompt: slide_system, user_prompt: slide_user, max_tokens: 4000)
      slides = parse_slides(result)
      html   = slides_to_html(slides)
      pptx_path = generate_pptx(slides)
      @outline.update!(content: html, slide_json: slides.to_json, status: :done)
      attach_pptx(pptx_path) if pptx_path
    else
      result = svc.call(system_prompt: generic_system, user_prompt: generic_user, max_tokens: 3000)
      @outline.update!(content: markdown_to_html(result), status: :done)
    end
  end

  private

  # ── AI prompts ──────────────────────────────────────────────────────────────

  def slide_system
    "Bạn là chuyên gia thiết kế slide thuyết trình chuyên nghiệp. Trả lời bằng tiếng Việt. Chỉ xuất đúng format được yêu cầu, không thêm văn bản khác."
  end

  def slide_user
    <<~PROMPT
      Tạo bộ slide thuyết trình CHUYÊN NGHIỆP, TRỰC QUAN cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      Tạo 8–10 slide, mỗi slide theo đúng format này:

      ---SLIDE---
      TITLE: Tiêu đề slide
      LAYOUT: [xem bên dưới]
      BODY:
      [nội dung theo từng LAYOUT]
      NOTE: Ghi chú ngắn cho người trình bày
      ---END---

      CÁC LOẠI LAYOUT VÀ FORMAT BODY:

      1. LAYOUT: bullets
         Dùng cho: nội dung có 3–4 điểm chính
         BODY format: mỗi dòng bắt đầu bằng "- " rồi nội dung cụ thể, có số liệu/ví dụ

      2. LAYOUT: stats
         Dùng cho: slide có 3–4 con số/chỉ số quan trọng (kết quả, số liệu thống kê)
         BODY format: mỗi dòng "- GIÁ_TRỊ :: MÔ_TẢ_NGẮN" (ví dụ: - 87% :: Học sinh đạt mục tiêu)

      3. LAYOUT: chart
         Dùng cho: so sánh theo thời gian, tiến trình, hoặc phân bổ theo nhóm
         BODY format: mỗi dòng "- SỐ :: NHÃN" (SỐ là số nguyên 0–100, ví dụ: - 45 :: Quý 1)
         Tối đa 5 cột.

      4. LAYOUT: two-col
         Dùng cho: so sánh 2 phía, pros/cons, trước/sau
         BODY format: dòng lẻ "- COL1: nội dung", dòng chẵn "- COL2: nội dung"
         Thêm dòng đầu tiên: "- HEADERS: Tiêu đề cột 1 | Tiêu đề cột 2"

      5. LAYOUT: timeline
         Dùng cho: các bước, giai đoạn, quy trình tuần tự
         BODY format: mỗi dòng "- BƯỚC_NGẮN :: Mô tả chi tiết" (tối đa 4 bước)

      YÊU CẦU NỘI DUNG:
      - Slide 1 (Bìa): LAYOUT: bullets, tiêu đề lớn + 2-3 từ khóa ngắn
      - Slide 2: Mục tiêu / Tổng quan — LAYOUT: bullets hoặc stats
      - Slide 3–4: Nội dung cốt lõi — ưu tiên dùng stats, chart, two-col để trực quan hóa
      - Slide 5–7: Phân tích sâu — dùng timeline hoặc two-col cho so sánh/quy trình
      - Slide áp chót: Case study / Ví dụ thực tế — LAYOUT: bullets hoặc two-col
      - Slide cuối: Tóm tắt — LAYOUT: bullets hoặc stats

      TIÊU CHUẨN:
      - Mỗi slide CÓ SỐ LIỆU cụ thể (%, số, tỉ lệ) khi có thể
      - Ưu tiên layout stats và chart cho các slide giữa (tránh dùng bullets cho quá nhiều slide liên tiếp)
      - NOTE phải là câu hỏi tương tác hoặc thông tin bổ sung có giá trị
    PROMPT
  end

  def generic_system
    "Bạn là trợ lý tạo nội dung giáo dục/đào tạo chuyên nghiệp. Trả lời bằng tiếng Việt với markdown rõ ràng."
  end

  def generic_user
    type_label = { "outline" => "dàn ý chi tiết", "lesson_plan" => "giáo án / kế hoạch buổi học" }[@outline.output_type] || "dàn ý"
    "Tạo #{type_label} cho chủ đề: \"#{@outline.title}\"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.\n\nYêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}\n\nTạo nội dung đầy đủ, có cấu trúc rõ ràng."
  end

  # ── Slide parsing & HTML viewer ─────────────────────────────────────────────

  def parse_slides(text)
    raw = text.scan(/---SLIDE---(.*?)---END---/m).flatten
    return [] if raw.empty?

    raw.map do |s|
      title  = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      layout = s[/LAYOUT:\s*(\S+)/, 1]&.strip&.downcase || "bullets"
      body   = s[/BODY:\n(.*?)(?:\nNOTE:|\z)/m, 1]&.strip || ""
      note   = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      lines  = body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)

      slide = { "title" => title, "layout" => layout, "note" => note }

      case layout
      when "stats"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0], "label" => parts[1] || "" }
        end
        slide["bullets"] = lines  # fallback
      when "chart"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0].to_i, "label" => parts[1] || "" }
        end
        slide["bullets"] = lines
      when "two-col"
        headers_line = lines.find { |l| l.start_with?("HEADERS:") }
        headers = headers_line ? headers_line.sub("HEADERS:", "").split("|").map(&:strip) : ["", ""]
        col1 = lines.select { |l| l.start_with?("COL1:") }.map { |l| l.sub("COL1:", "").strip }
        col2 = lines.select { |l| l.start_with?("COL2:") }.map { |l| l.sub("COL2:", "").strip }
        slide["headers"] = headers
        slide["col1"] = col1
        slide["col2"] = col2
        slide["bullets"] = lines.reject { |l| l.start_with?("HEADERS:") }
      when "timeline"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "step" => parts[0], "desc" => parts[1] || "" }
        end
        slide["bullets"] = lines
      else
        slide["bullets"] = lines
      end

      slide
    end
  end

  def slides_to_html(slides)
    return "<p>Không thể tạo slide.</p>" if slides.empty?
    "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides.to_json)}'></div>"
  end

  # ── PPTX generation ─────────────────────────────────────────────────────────

  def generate_pptx(slides)
    return nil if slides.empty?
    return nil unless File.exist?(PPTX_SCRIPT)

    out_path = Rails.root.join("tmp", "slide_#{@outline.id}_#{Time.now.to_i}.pptx").to_s
    require "open3"
    stdout, stderr, status = Open3.capture3(
      "python3", PPTX_SCRIPT, slides.to_json, out_path
    )
    Rails.logger.error "[PPTX] #{stderr}" if stderr.present?
    status.success? && File.exist?(out_path) ? out_path : nil
  rescue => e
    Rails.logger.error "[PPTX] #{e.message}"
    nil
  end

  def attach_pptx(path)
    filename = "#{@outline.title.parameterize}.pptx"
    @outline.pptx_file.attach(
      io: File.open(path),
      filename: filename,
      content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    )
  ensure
    File.delete(path) rescue nil
  end

  # ── Markdown → HTML ─────────────────────────────────────────────────────────

  def markdown_to_html(text)
    colors = %w[#10b981 #f59e0b #6366f1 #3b82f6 #ec4899]
    ci = 0
    text.gsub(/^## (.+)$/) { c = colors[ci % colors.size]; ci += 1; "<h2 style='border-left:4px solid #{c};padding-left:10px;color:#{c};margin:20px 0 8px'>#{$1}</h2>" }
        .gsub(/^### (.+)$/, '<h3 style="font-weight:700;margin:12px 0 4px;color:#334155">\1</h3>')
        .gsub(/^# (.+)$/,   '<h1 style="font-size:1.3em;font-weight:800;margin:0 0 16px;color:#1e293b">\1</h1>')
        .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        .gsub(/^- (.+)$/,   '<li style="margin:3px 0 3px 16px">\1</li>')
        .gsub(/^(\d+)\. (.+)$/, '<li style="margin:3px 0 3px 16px;list-style:decimal">\2</li>')
        .gsub(/^---$/, '<hr style="border:none;border-top:1px solid #e2e8f0;margin:16px 0">')
        .gsub(/\n\n/, '</p><p style="margin:8px 0">')
        .then { |t| "<p style='margin:8px 0'>#{t}</p>" }
  end
end
