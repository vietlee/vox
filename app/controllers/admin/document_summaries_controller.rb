class Admin::DocumentSummariesController < Admin::BaseController
  before_action :set_summary, only: [:show, :destroy]

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
    generate_summary(@summary)
    deduct_credits!(2)
    redirect_to document_summary_path(@summary)
  rescue => e
    @summary&.update_columns(status: 2)
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  def show; end

  def destroy
    @summary.destroy
    redirect_to document_summaries_path, notice: "Đã xóa."
  end

  private

  def set_summary
    @summary = current_workspace.document_summaries.find(params[:id])
  end

  def generate_summary(summary)
    text = summary.source_text.presence
    if text.blank? && summary.source_file.attached?
      # Extract text from attached file (basic)
      text = summary.source_file.download.force_encoding("UTF-8").scrub
    end
    return summary.update!(status: :failed) if text.blank?

    text_input = text.to_s.truncate(15000)
    svc = ClaudeService.for_feature("feedback_analysis", timeout: 180)
    result = svc.call(
      system_prompt: "Bạn là trợ lý tóm tắt tài liệu chuyên nghiệp. Trả về JSON hợp lệ.",
      user_prompt: "Tóm tắt tài liệu sau.\n\nTài liệu:\n#{text_input}\n\nJSON: {\"summary\":\"tóm tắt tổng quan 3-5 câu\",\"key_points\":[\"điểm chính 1\",\"điểm chính 2\",...],\"title_suggestion\":\"tiêu đề gợi ý nếu không có\"}",
      max_tokens: 2000
    )
    data = JSON.parse(result.match(/\{.*\}/m)&.to_s || result)
    summary.update!(
      summary:    data["summary"],
      key_points: data["key_points"].to_json,
      title:      summary.title.presence || data["title_suggestion"],
      status:     :done
    )
  end
end
