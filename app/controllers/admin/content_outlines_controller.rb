class Admin::ContentOutlinesController < Admin::BaseController
  before_action :set_outline, only: [:show, :destroy, :regenerate, :status, :update_slides, :ai_edit, :change_theme]

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
    render json: { pending: @outline.pending?, failed: @outline.failed?, show_url: content_outline_path(@outline) }
  end

  def regenerate
    @outline.update!(status: :pending, content: nil, slide_json: nil)
    @outline.pptx_file.purge if @outline.pptx_file.attached?
    @outline.slide_images.purge if @outline.slide_images.attached?
    GenerateContentOutlineJob.perform_later(@outline.id)
    respond_to do |format|
      format.json { render json: { pending: true, poll_url: status_content_outline_path(@outline, format: :json) } }
      format.html { redirect_to content_outline_path(@outline) }
    end
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

  def change_theme
    theme_name = params[:theme].to_s.strip.downcase
    return render json: { error: "Invalid theme" }, status: 422 unless theme_name.present?

    current_deck = JSON.parse(@outline.slide_json || "{}")
    current_slides = current_deck["slides"] || []
    raw_slides = current_slides.map { |s| s["raw"] || s }
    return render json: { error: "No slides to recompile" }, status: 422 if raw_slides.empty?

    gen = ContentOutlineGenerator.new(@outline)
    deck = gen.recompile(raw_slides, theme_name)

    # Preserve manually-added elements (images, extra text boxes, etc.) from each slide
    deck["slides"].each_with_index do |new_slide, i|
      old_slide = current_slides[i]
      next unless old_slide

      # Keep background if user explicitly set a solid color
      if old_slide["background"].is_a?(Hash) && old_slide["background"]["type"] == "solid"
        new_slide["background"] = old_slide["background"]
      end

      # Merge elements: keep AI-generated ones from new theme, append user-added ones
      old_els = old_slide["elements"] || []
      new_els = new_slide["elements"] || []
      new_ids = new_els.map { |e| e["id"] }.to_set

      # User-added elements are those not present in the newly compiled slide
      user_added = old_els.reject { |e| new_ids.include?(e["id"]) }
      new_slide["elements"] = new_els + user_added unless user_added.empty?

      # Preserve text edits on existing elements
      old_els.each do |old_el|
        new_el = new_els.find { |e| e["id"] == old_el["id"] }
        next unless new_el
        new_el["content"] = old_el["content"] if old_el["content"].present?
        new_el["style"] = (new_el["style"] || {}).merge(old_el["style"] || {}) if old_el["style"].present?
        new_el["x"] = old_el["x"]; new_el["y"] = old_el["y"]
        new_el["w"] = old_el["w"]; new_el["h"] = old_el["h"]
      end
    end

    html = "<div id='slide-deck-root' data-deck='#{ERB::Util.html_escape(deck.to_json)}'></div>"
    @outline.update!(slide_json: deck.to_json, content: html)

    # Regenerate PPTX so downloads match the new theme
    @outline.pptx_file.purge if @outline.pptx_file.attached?
    gen.recompile_and_export(raw_slides, theme_name)

    render json: { deck: deck }
  rescue => e
    render json: { error: e.message }, status: 422
  end

  def update_slides
    deck_json = params[:deck_json] || params[:slide_json]
    return render json: { error: "Missing deck_json" }, status: 422 if deck_json.blank?

    deck = JSON.parse(deck_json)
    html = "<div id='slide-deck-root' data-deck='#{ERB::Util.html_escape(deck.to_json)}'></div>"
    @outline.update!(slide_json: deck.to_json, content: html)
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
