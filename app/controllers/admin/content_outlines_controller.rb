class Admin::ContentOutlinesController < Admin::BaseController
  before_action :set_outline, only: [:show, :destroy, :regenerate]

  def index
    @outlines = current_workspace.content_outlines.includes(:created_by).order(created_at: :desc)
  end

  def new
    @outline = ContentOutline.new
  end

  def create
    @outline = current_workspace.content_outlines.new(outline_params.merge(created_by: current_user, status: :pending))
    @outline.save!
    generate_outline(@outline)
    redirect_to content_outline_path(@outline)
  rescue => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def show; end

  def regenerate
    @outline.update!(status: :pending, content: nil)
    generate_outline(@outline)
    redirect_to content_outline_path(@outline)
  end

  def destroy
    @outline.destroy
    redirect_to content_outlines_path, notice: "Đã xóa."
  end

  private

  def set_outline
    @outline = current_workspace.content_outlines.find(params[:id])
  end

  def outline_params
    params.require(:content_outline).permit(:title, :subject, :output_type, :prompt_input)
  end

  def generate_outline(outline)
    svc = ClaudeService.for_feature("quiz_generate", timeout: 120)

    if outline.output_type == "slide"
      system_prompt = "Bạn là chuyên gia tạo slide thuyết trình. Trả lời bằng tiếng Việt."
      user_prompt = <<~PROMPT
        Tạo bộ slide thuyết trình cho chủ đề: "#{outline.title}"#{outline.subject.present? ? " (#{outline.subject})" : ""}.
        Yêu cầu bổ sung: #{outline.prompt_input.presence || 'Không có'}

        Tạo 6–10 slide. Mỗi slide PHẢI theo đúng format sau (không thêm gì khác):

        ---SLIDE---
        TITLE: Tiêu đề slide
        BODY:
        - Điểm chính 1
        - Điểm chính 2
        - Điểm chính 3
        NOTE: Ghi chú cho người trình bày (1-2 câu ngắn)
        ---END---

        Slide đầu tiên là trang bìa (title slide), slide cuối là tóm tắt/kết luận.
        Mỗi slide tối đa 5 bullet points. Ngắn gọn, súc tích, dễ nhớ.
      PROMPT
      result = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 3000)
      html = slides_to_html(result)
    else
      type_label = { "outline" => "dàn ý chi tiết", "lesson_plan" => "giáo án / kế hoạch buổi học" }[outline.output_type] || "dàn ý"
      system_prompt = "Bạn là trợ lý tạo nội dung giáo dục/đào tạo chuyên nghiệp. Trả lời bằng tiếng Việt với markdown rõ ràng."
      user_prompt = "Tạo #{type_label} cho chủ đề: \"#{outline.title}\"#{outline.subject.present? ? " (môn/lĩnh vực: #{outline.subject})" : ""}.\n\nYêu cầu bổ sung: #{outline.prompt_input.presence || 'Không có'}\n\nTạo nội dung đầy đủ, có cấu trúc rõ ràng với tiêu đề, nội dung chính, ví dụ thực tế."
      result = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 3000)
      html = markdown_to_html(result)
    end

    outline.update!(content: html, status: :done)
  end

  def slides_to_html(text)
    raw_slides = text.scan(/---SLIDE---(.*?)---END---/m).flatten
    return markdown_to_html(text) if raw_slides.empty?

    slides_json = raw_slides.map do |s|
      title = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      body_raw = s[/BODY:\n(.*?)(?:NOTE:|$)/m, 1]&.strip || ""
      note = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      bullets = body_raw.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)
      { title: title, bullets: bullets, note: note }
    end

    json_str = slides_json.to_json.gsub("'", "\\'")
    "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides_json.to_json)}'></div>"
  end

  def markdown_to_html(text)
    colors = %w[#10b981 #f59e0b #6366f1 #3b82f6 #ec4899]
    color_idx = 0
    text.gsub(/^## (.+)$/) { |_| c = colors[color_idx % colors.size]; color_idx += 1; "<h2 style='border-left:4px solid #{c};padding-left:10px;color:#{c};margin:20px 0 8px'>#{$1}</h2>" }
        .gsub(/^### (.+)$/, '<h3 style="font-weight:700;margin:12px 0 4px;color:#334155">\1</h3>')
        .gsub(/^# (.+)$/, '<h1 style="font-size:1.3em;font-weight:800;margin:0 0 16px;color:#1e293b">\1</h1>')
        .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        .gsub(/^- (.+)$/, '<li style="margin:3px 0 3px 16px">\1</li>')
        .gsub(/^(\d+)\. (.+)$/, '<li style="margin:3px 0 3px 16px;list-style:decimal">\2</li>')
        .gsub(/^---$/, '<hr style="border:none;border-top:1px solid #e2e8f0;margin:16px 0">')
        .gsub(/\n\n/, '</p><p style="margin:8px 0">')
        .then { |t| "<p style='margin:8px 0'>#{t}</p>" }
  end
end
