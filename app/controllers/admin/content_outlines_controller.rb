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
    type_label = { "outline" => "dàn ý chi tiết", "slide_script" => "nội dung slide thuyết trình", "lesson_plan" => "giáo án / kế hoạch buổi học" }[outline.output_type] || "dàn ý"
    system_prompt = "Bạn là trợ lý tạo nội dung giáo dục/đào tạo chuyên nghiệp. Trả lời bằng tiếng Việt với markdown rõ ràng. Không dùng từ ngữ chỉ riêng giáo viên/học sinh — hướng tới mọi loại người tổ chức và người tham gia."
    user_prompt = "Tạo #{type_label} cho chủ đề: \"#{outline.title}\"#{outline.subject.present? ? " (môn/lĩnh vực: #{outline.subject})" : ""}.\n\nYêu cầu bổ sung: #{outline.prompt_input.presence || 'Không có'}\n\nTạo nội dung đầy đủ, có cấu trúc rõ ràng với tiêu đề, nội dung chính, ví dụ thực tế."
    svc = ClaudeService.for_feature("quiz_generate", timeout: 120)
    result = svc.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 3000)
    html = markdown_to_html(result)
    outline.update!(content: html, status: :done)
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
