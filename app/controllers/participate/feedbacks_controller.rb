class Participate::FeedbacksController < Participate::BaseController
  before_action :set_board

  def show
    unless @board.active?
      render :closed and return
    end
    @feedbacks = @board.feedbacks.visible.pinned_first.limit(50)
    @feedback  = @board.feedbacks.build
  end

  def submit
    @feedback = @board.feedbacks.build(
      workspace: @board.workspace,
      content: params[:feedback][:content],
      author_name: params[:feedback][:author_name],
      author_email: params[:feedback][:author_email],
      anonymous: params[:feedback][:anonymous] == "1"
    )

    if @feedback.save
      if @board.manual_approval?
        flash[:notice] = t("feedbacks.pending_approval")
      else
        @feedback.approve! unless @board.auto_moderation?
      end
      redirect_to participate_feedback_path(@board.slug)
    else
      @feedbacks = @board.feedbacks.visible.pinned_first.limit(50)
      render :show, status: :unprocessable_entity
    end
  end

  def upvote
    feedback = @board.feedbacks.visible.find(params[:feedback_id] || params[:id])
    token = respondent_token

    if feedback.upvoted_by?(token)
      feedback.feedback_upvotes.find_by(voter_token: token)&.destroy
      render json: { count: feedback.reload.upvotes_count, upvoted: false }
    else
      feedback.feedback_upvotes.create!(voter_token: token)
      render json: { count: feedback.reload.upvotes_count, upvoted: true }
    end
  end

  private

  def set_board
    @board = FeedbackBoard.find_by!(slug: params[:slug])
    @workspace = @board.workspace
  end
end
