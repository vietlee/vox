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
    "Bạn là chuyên gia tạo slide thuyết trình chuyên nghiệp. Trả lời bằng tiếng Việt."
  end

  def slide_user
    <<~PROMPT
      Tạo bộ slide thuyết trình CHUYÊN NGHIỆP cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      Tạo 8–10 slide chất lượng cao, mỗi slide theo đúng format này (không thêm gì khác):

      ---SLIDE---
      TITLE: Tiêu đề rõ ràng, hấp dẫn
      BODY:
      - Nội dung cụ thể, có số liệu hoặc ví dụ thực tế khi có thể
      - Mỗi bullet là một ý hoàn chỉnh, giá trị cao (không chung chung)
      - Tối đa 4 bullets, mỗi bullet 8–15 từ
      NOTE: Ghi chú 1-2 câu cho người trình bày: giải thích sâu hơn, ví dụ thực tế, hoặc câu hỏi tương tác
      ---END---

      Yêu cầu nội dung:
      - Slide 1 (Bìa): tiêu đề chính + 2-3 từ khóa/điểm nhấn ngắn ở BODY
      - Slide 2: Tổng quan / Mục tiêu — người nghe sẽ học được gì
      - Slide 3-7: Nội dung cốt lõi, mỗi slide một chủ đề riêng biệt, có chiều sâu
      - Slide áp chót: Ứng dụng thực tế / Case study
      - Slide cuối: Tóm tắt điểm chính + Call-to-action cụ thể

      Tiêu chuẩn chất lượng:
      - Bullets phải CỤ THỂ: có số liệu, ví dụ, hoặc hành động rõ ràng (tránh câu chung chung như "rất quan trọng")
      - Flow logic: mỗi slide dẫn tự nhiên sang slide tiếp theo
      - NOTE phải hữu ích: câu hỏi tương tác hoặc thông tin bổ sung thực chất
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
      title   = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      body    = s[/BODY:\n(.*?)(?:NOTE:|$)/m, 1]&.strip || ""
      note    = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      bullets = body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)
      { "title" => title, "bullets" => bullets, "note" => note }
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
