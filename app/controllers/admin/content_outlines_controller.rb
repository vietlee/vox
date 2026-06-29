class Admin::ContentOutlinesController < Admin::BaseController
  before_action :set_outline, only: [:show, :destroy, :regenerate, :status, :update_slides, :ai_edit, :change_theme, :toggle_share, :revoke_share, :regenerate_share]

  def index
    @outlines = current_workspace.content_outlines.includes(:created_by).order(created_at: :desc)
    if (q = params[:q].to_s.strip).present?
      @outlines = @outlines.where("title ILIKE ?", "%#{q}%")
    end
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

  def show
    @share_qr = QrCode.find_by(resource: @outline, workspace: current_workspace)
    # Auto-create QR if share link exists but QR record was never generated
    if @outline.share_token.present? && @share_qr.nil?
      @share_qr = QrCode.create!(resource: @outline, workspace: current_workspace,
                                  token: SecureRandom.urlsafe_base64(12))
    end
  end

  def status
    render json: {
      pending:   @outline.pending?,
      failed:    @outline.failed?,
      show_url:  content_outline_path(@outline),
      deck_json: (@outline.done? && @outline.slide_json.present?) ? @outline.slide_json : nil
    }
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

      # Only keep user-added elements that are NOT theme decorations.
      # rect/ellipse/line are always AI-generated decorations — never user-added.
      # Keep only image, video, icon, chart_*, and text boxes not present in new theme.
      user_kept_types = %w[image video icon text chart_bar chart_donut]
      user_added = old_els.reject do |e|
        new_ids.include?(e["id"]) || !user_kept_types.any? { |t| e["type"].to_s.start_with?(t) }
      end
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

  def toggle_share
    ensure_share_assets!
    url    = public_slide_url(@outline.share_token)
    qr     = QrCode.find_by(resource: @outline, workspace: current_workspace)
    render json: { ok: true, url: url,
                   qr_image_url: qr ? qr_image_url(token: qr.token) : nil,
                   active: true }
  end

  def revoke_share
    QrCode.where(resource: @outline, workspace: current_workspace).destroy_all
    @outline.update!(share_token: nil)
    render json: { ok: true }
  end

  def regenerate_share
    QrCode.where(resource: @outline, workspace: current_workspace).destroy_all
    @outline.update!(share_token: SecureRandom.urlsafe_base64(12))
    ensure_share_assets!
    url  = public_slide_url(@outline.share_token)
    qr   = QrCode.find_by(resource: @outline, workspace: current_workspace)
    render json: { ok: true, url: url,
                   qr_image_url: qr ? qr_image_url(token: qr.token) : nil }
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

  def extract_text
    file = params[:file]
    return render json: { error: "Không có file" }, status: :bad_request unless file

    ext = File.extname(file.original_filename).downcase
    text = case ext
           when ".pdf"   then extract_pdf(file)
           when ".docx"  then extract_docx(file)
           when ".doc"   then extract_doc(file)
           when ".txt"   then file.read.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
           else nil
           end

    if text.blank?
      render json: { error: "Không thể đọc file này. Thử PDF hoặc DOCX." }
    else
      render json: { text: text.strip[0, 15_000] }
    end
  end

  private

  def ensure_share_assets!
    @outline.generate_share_token
    @outline.save! if @outline.share_token_changed?
    QrCode.find_or_create_by!(resource: @outline, workspace: current_workspace) do |q|
      q.token = SecureRandom.urlsafe_base64(12)
    end
  end

  def set_outline
    @outline = current_workspace.content_outlines.find(params[:id])
  end

  def outline_params
    params.require(:content_outline).permit(:title, :subject, :output_type, :prompt_input, :source_document_text)
  end

  def extract_pdf(file)
    require "open3"
    data = file.read
    tmp = Tempfile.new(["co_upload", ".pdf"])
    tmp.binmode; tmp.write(data); tmp.flush
    stdout, _stderr, status = Open3.capture3("pdftotext", "-enc", "UTF-8", tmp.path, "-")
    if status.success? && stdout.strip.present?
      tmp.close!; return stdout.strip
    end
    begin
      require "pdf-reader"
      reader = PDF::Reader.new(StringIO.new(data))
      text = reader.pages.map(&:text).join("\n").strip
      tmp.close!; return text if text.present?
    rescue; end
    tmp.close!; nil
  rescue; nil
  end

  def extract_docx(file)
    require "zip"
    io = StringIO.new(file.read)
    Zip::File.open_buffer(io) do |zip|
      entry = zip.find_entry("word/document.xml")
      return nil unless entry
      xml = entry.get_input_stream.read.force_encoding("UTF-8")
      xml.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end
  rescue; nil
  end

  def extract_doc(file)
    require "open3"
    tmp = Tempfile.new(["co_doc", ".doc"])
    tmp.binmode; tmp.write(file.read); tmp.flush
    stdout, _stderr, status = Open3.capture3("antiword", tmp.path)
    tmp.close!
    status.success? && stdout.strip.present? ? stdout.strip : nil
  rescue; nil
  end
end
