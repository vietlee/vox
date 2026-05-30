class Admin::FeedbackBoardsController < Admin::BaseController
  before_action :set_board, only: [:show, :edit, :update, :destroy, :close, :reopen, :export, :ai_summarize]

  def index
    @q = params[:q].to_s.strip
    boards = current_workspace.feedback_boards.order(created_at: :desc)
    boards = boards.where("title ILIKE ? OR description ILIKE ?", "%#{@q}%", "%#{@q}%") if @q.present?
    @pagy, @boards = pagy(boards, items: 12)
  end

  def show
  end

  def new
    @board = current_workspace.feedback_boards.build
  end

  def create
    subscription = current_workspace.active_subscription
    unless subscription&.within_feedback_limit?
      msg = subscription&.free? ? t("feedback_boards.limit_reached_free", date: subscription.next_reset_date_formatted) : t("feedback_boards.limit_reached")
      redirect_to feedback_boards_path, alert: msg
      return
    end

    @board = current_workspace.feedback_boards.build(board_params)
    @board.user = current_user

    # Default to workspace's most recently uploaded logo if none provided
    unless @board.logo.attached?
      last_logo_board = current_workspace.feedback_boards.joins(:logo_attachment).order("active_storage_attachments.created_at DESC").first
      @board.logo.attach(last_logo_board.logo.blob) if last_logo_board&.logo&.attached?
    end

    if @board.save
      audit_log("feedback_board.create", resource: @board)
      current_workspace.increment!(:feedbacks_created_count)
      redirect_to feedback_board_path(@board), notice: t("feedback_boards.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    remove_logo = params.dig(:feedback_board, :remove_logo) == "1"
    if @board.update(board_params)
      @board.logo.purge if remove_logo && @board.logo.attached?
      audit_log("feedback_board.update", resource: @board)
      redirect_to edit_feedback_board_path(@board), notice: t("feedback_boards.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy
    redirect_to feedback_boards_path
  end

  def close
    @board.update!(status: :closed)
    audit_log("feedback_board.close", resource: @board)
    redirect_to feedback_board_path(@board), notice: t("feedback_boards.closed")
  end

  def reopen
    @board.update!(status: :active)
    audit_log("feedback_board.reopen", resource: @board)
    redirect_to feedback_board_path(@board), notice: t("feedback_boards.reopened")
  end

  def export
    require "csv"
    feedbacks = @board.feedbacks.approved.order(created_at: :desc)

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["#", t("feedbacks.created_at", default: "Thời gian"), t("feedbacks.author", default: "Tác giả"), t("feedbacks.content", default: "Nội dung"), t("feedbacks.upvotes", default: "Upvotes"), t("feedbacks.status", default: "Trạng thái")]
      feedbacks.each_with_index do |fb, idx|
        csv << [
          idx + 1,
          I18n.l(fb.created_at, format: :short),
          fb.anonymous? ? t("feedback_boards.feedbacks_page.anonymous") : (fb.author_name.presence || fb.author_email || "—"),
          fb.content,
          fb.upvotes_count,
          t("status.#{fb.status}")
        ]
      end
    end

    filename = "#{@board.title.parameterize}-feedbacks-#{Date.today}.csv"
    send_data "\xEF\xBB\xBF#{csv_data}", filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  def ai_summarize
    return unless require_ai_feature!(:ai_analysis)
    return unless require_credits!(3)

    language = params[:language].presence_in(%w[vi en]) || current_workspace.language || "vi"
    current_workspace.active_subscription&.deduct_credits!(3)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "feedback_analysis", resource_type: "FeedbackBoard", resource_id: @board.id, credits_cost: 3, input_data: { language: language })
    AiFeedbackAnalysisJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  private

  def set_board
    @board = current_workspace.feedback_boards.find(params[:id])
  end

  def board_params
    params.require(:feedback_board).permit(:title, :description, :identity_mode, :auto_moderation, :manual_approval, :allow_replies, :allow_upvotes, :logo)
  end
end
