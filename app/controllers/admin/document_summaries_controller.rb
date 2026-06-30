class Admin::DocumentSummariesController < Admin::BaseController
  before_action :set_summary, only: [:show, :destroy, :ai_status]

  def index
    @summaries = current_workspace.document_summaries.includes(:created_by).order(created_at: :desc)
  end

  def new; @summary = DocumentSummary.new; end

  def create
    return unless require_credits!(2)

    @summary = current_workspace.document_summaries.new(
      title:        params[:title].to_s.strip,
      source_type:  params[:source_type],
      created_by:   current_user,
      status:       :pending
    )

    if params[:source_file].present?
      ext = File.extname(params[:source_file].original_filename.to_s).delete(".").downcase
      @summary.source_type  = ext.in?(%w[pdf docx doc txt csv xlsx xls pptx]) ? ext : (params[:source_file].content_type.to_s.start_with?("image/") ? "image" : ext)
      @summary.source_file.attach(params[:source_file])
      @summary.source_filename = params[:source_file].original_filename
    elsif params[:source_text].present?
      @summary.source_text = params[:source_text].to_s.strip
    end

    @summary.save!
    GenerateDocumentSummaryJob.perform_later(@summary.id)

    respond_to do |format|
      format.json { render json: { pending: true, poll_url: ai_status_document_summary_path(@summary, format: :json), show_url: document_summary_path(@summary) } }
      format.html { redirect_to document_summary_path(@summary) }
    end
  rescue => e
    @summary&.update_columns(status: 2)
    respond_to do |format|
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
      format.html { flash.now[:alert] = e.message; render :new, status: :unprocessable_entity }
    end
  end

  def show; end

  def ai_status
    if @summary.pending?
      # Auto-fail after 10 minutes to prevent infinite polling
      if @summary.created_at < 10.minutes.ago
        @summary.update_columns(status: 2)
        render json: { failed: true, error: "Xử lý quá thời gian. Vui lòng thử lại." }
      else
        render json: { pending: true }
      end
    elsif @summary.failed?
      render json: { failed: true, error: "AI gặp lỗi khi tóm tắt. Vui lòng thử lại." }
    else
      render json: { success: true, redirect: document_summary_path(@summary) }
    end
  end

  def destroy
    @summary.destroy
    redirect_to document_summaries_path, notice: "Đã xóa."
  end

  private

  def set_summary
    @summary = current_workspace.document_summaries.find(params[:id])
  end
end
