class Admin::FeedbacksController < Admin::BaseController
  before_action :set_board
  before_action :set_feedback, only: [:show, :update, :destroy, :approve, :hide, :pin, :unpin, :update_admin_status]

  def index
    feedbacks = @board.feedbacks.order(pinned: :desc, created_at: :desc)
    feedbacks = feedbacks.where(status: params[:status]) if params[:status].present?
    feedbacks = feedbacks.where(moderation_status: params[:moderation]) if params[:moderation].present?
    @pagy, @feedbacks = pagy(feedbacks)
  end

  def show
  end

  def update
    @feedback.update(feedback_update_params)
    redirect_back(fallback_location: feedback_board_feedbacks_path(@board))
  end

  def destroy
    @feedback.destroy
    redirect_to feedback_board_feedbacks_path(@board)
  end

  def approve
    @feedback.update!(status: :approved)
    respond_to do |format|
      format.html { redirect_back(fallback_location: feedback_board_feedbacks_path(@board)) }
      format.turbo_stream
    end
  end

  def hide
    @feedback.update!(status: :hidden)
    respond_to { |f| f.turbo_stream }
  end

  def pin
    @feedback.update!(pinned: true)
    respond_to { |f| f.turbo_stream }
  end

  def unpin
    @feedback.update!(pinned: false)
    respond_to { |f| f.turbo_stream }
  end

  def update_admin_status
    @feedback.update!(admin_status: params[:admin_status])
    respond_to { |f| f.turbo_stream }
  end

  private

  def set_board
    @board = current_workspace.feedback_boards.find(params[:feedback_board_id])
  end

  def set_feedback
    @feedback = @board.feedbacks.find(params[:id])
  end

  def feedback_update_params
    params.require(:feedback).permit(:admin_reply, :admin_status, :status, :pinned)
  end
end
