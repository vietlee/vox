class Admin::FeedbackBoardsController < Admin::BaseController
  before_action :set_board, only: [:show, :edit, :update, :destroy, :close, :export, :ai_summarize]

  def index
    @pagy, @boards = pagy(current_workspace.feedback_boards.order(created_at: :desc))
  end

  def show
  end

  def new
    @board = current_workspace.feedback_boards.build
  end

  def create
    @board = current_workspace.feedback_boards.build(board_params)
    @board.user = current_user
    if @board.save
      redirect_to feedback_board_feedbacks_path(@board), notice: t("feedback_boards.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @board.update(board_params)
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
    redirect_to feedback_boards_path
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
    params.require(:feedback_board).permit(:title, :description, :identity_mode, :auto_moderation, :manual_approval, :allow_replies, :allow_upvotes)
  end
end
