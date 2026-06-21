class ContentOutlineGenerator
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
      html = slides_to_html(result)
    else
      result = svc.call(system_prompt: generic_system, user_prompt: generic_user, max_tokens: 3000)
      html = markdown_to_html(result)
    end

    @outline.update!(content: html, status: :done)
  end

  private

  def slide_system
    "Bạn là chuyên gia tạo slide thuyết trình. Trả lời bằng tiếng Việt."
  end

  def slide_user
    <<~PROMPT
      Tạo bộ slide thuyết trình cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      Tạo 6–8 slide. Mỗi slide theo đúng format (không thêm gì khác):

      ---SLIDE---
      TITLE: Tiêu đề slide
      BODY:
      - Điểm chính 1
      - Điểm chính 2
      - Điểm chính 3
      NOTE: Ghi chú ngắn cho người trình bày
      ---END---

      Slide đầu là trang bìa, slide cuối là tóm tắt. Mỗi slide tối đa 4 bullets.
    PROMPT
  end

  def generic_system
    "Bạn là trợ lý tạo nội dung giáo dục/đào tạo chuyên nghiệp. Trả lời bằng tiếng Việt với markdown rõ ràng."
  end

  def generic_user
    type_label = { "outline" => "dàn ý chi tiết", "lesson_plan" => "giáo án / kế hoạch buổi học" }[@outline.output_type] || "dàn ý"
    "Tạo #{type_label} cho chủ đề: \"#{@outline.title}\"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.\n\nYêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}\n\nTạo nội dung đầy đủ, có cấu trúc rõ ràng."
  end

  def slides_to_html(text)
    raw_slides = text.scan(/---SLIDE---(.*?)---END---/m).flatten
    return markdown_to_html(text) if raw_slides.empty?

    slides_json = raw_slides.map do |s|
      title   = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      body    = s[/BODY:\n(.*?)(?:NOTE:|$)/m, 1]&.strip || ""
      note    = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      bullets = body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)
      { title: title, bullets: bullets, note: note }
    end

    "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides_json.to_json)}'></div>"
  end

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
