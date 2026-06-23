class Admin::ContentOutlinesController < Admin::BaseController
  before_action :set_outline, only: [:show, :destroy, :regenerate, :status, :update_slides, :ai_edit]

  def index
    @outlines = current_workspace.content_outlines.includes(:created_by).order(created_at: :desc)
  end

  def new
    @outline = ContentOutline.new
  end

  def create
    @outline = current_workspace.content_outlines.new(outline_params.merge(created_by: current_user, status: :pending))
    @outline.save!
    GenerateContentOutlineJob.perform_later(@outline.id)

    respond_to do |format|
      format.json { render json: { pending: true, poll_url: status_content_outline_path(@outline, format: :json), show_url: content_outline_path(@outline) } }
      format.html { redirect_to content_outline_path(@outline) }
    end
  rescue => e
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { flash.now[:alert] = e.message; render :new, status: :unprocessable_entity }
    end
  end

  def show; end

  def status
    is_slide = @outline.output_type == "slide"
    images_ready = is_slide ? @outline.slide_images.attached? : true
    still_pending = @outline.pending? || (is_slide && @outline.done? && !images_ready)
    render json: { pending: still_pending, failed: @outline.failed?, show_url: content_outline_path(@outline) }
  end

  def regenerate
    @outline.update!(status: :pending, content: nil, slide_json: nil)
    @outline.pptx_file.purge if @outline.pptx_file.attached?
    @outline.slide_images.purge if @outline.slide_images.attached?
    GenerateContentOutlineJob.perform_later(@outline.id)
    redirect_to content_outline_path(@outline)
  end

  def ai_edit
    edit_prompt = params[:edit_prompt].to_s.strip
    return render json: { error: "Vui lòng nhập yêu cầu chỉnh sửa" }, status: 422 if edit_prompt.blank?

    @outline.update!(status: :pending)
    @outline.pptx_file.purge if @outline.pptx_file.attached?
    @outline.slide_images.purge if @outline.slide_images.attached?
    @outline.edit_images.purge if @outline.edit_images.attached?

    if params[:images].present?
      params[:images].each { |img| @outline.edit_images.attach(img) }
    end

    AiEditSlideJob.perform_later(@outline.id, edit_prompt)
    render json: { pending: true, poll_url: status_content_outline_path(@outline, format: :json) }
  end

  def destroy
    @outline.destroy
    redirect_to content_outlines_path, notice: "Đã xóa."
  end

  def update_slides
    slide_json = params[:slide_json]
    return render json: { error: "Missing slide_json" }, status: 422 if slide_json.blank?

    slides = JSON.parse(slide_json)
    theme  = @outline.content&.[](/data-theme='([^']+)'/, 1) || ""
    theme_attr = theme.present? ? " data-theme='#{ERB::Util.html_escape(theme)}'" : ""
    html   = "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides.to_json)}'#{theme_attr}></div>"
    @outline.update!(slide_json: slides.to_json, content: html)
    render json: { ok: true }
  rescue JSON::ParserError
    render json: { error: "Invalid JSON" }, status: 422
  end

  private

  def set_outline
    @outline = current_workspace.content_outlines.find(params[:id])
  end

  def outline_params
    params.require(:content_outline).permit(:title, :subject, :output_type, :prompt_input)
  end
end
