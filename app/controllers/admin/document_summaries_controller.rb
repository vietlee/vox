class Admin::DocumentSummariesController < Admin::BaseController
  before_action :set_summary, only: [:show, :destroy, :ai_status]

  def index
    @summaries = current_workspace.document_summaries.includes(:created_by).order(created_at: :desc)
  end

  def new; @summary = DocumentSummary.new; end

  def create
    @summary = current_workspace.document_summaries.new(
      title:        params[:title].to_s.strip,
      source_type:  params[:source_type],
      created_by:   current_user,
      status:       :pending
    )

    if params[:source_file].present?
      @summary.source_file.attach(params[:source_file])
      @summary.source_filename = params[:source_file].original_filename
    elsif params[:source_text].present?
      @summary.source_text = params[:source_text].to_s.strip
    end

    @summary.save!
    require_credits!(2)
    deduct_credits!(2)
    GenerateDocumentSummaryJob.perform_later(@summary.id)
    redirect_to document_summary_path(@summary)
  rescue => e
    @summary&.update_columns(status: 2)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def show; end

  def ai_status
    render json: { pending: @summary.pending?, failed: @summary.failed? }
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
