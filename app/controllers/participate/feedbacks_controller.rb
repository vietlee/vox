class Participate::FeedbacksController < Participate::BaseController
  before_action :set_board

  def show
    unless @board.active?
      render :closed and return
    end
    @feedbacks   = @board.feedbacks.visible.pinned_first.includes(:feedback_replies).limit(50)
    @feedback    = @board.feedbacks.build
    @upvoted_ids = FeedbackUpvote.where(feedback: @feedbacks, voter_token: respondent_token).pluck(:feedback_id).to_set
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

  def reply
    unless @board.allow_replies?
      render json: { error: "Replies not allowed" }, status: :forbidden and return
    end
    feedback = @board.feedbacks.visible.find(params[:feedback_id])
    anonymous = params[:reply][:author_name].blank?
    reply = feedback.feedback_replies.create!(
      content:     params[:reply][:content],
      author_name: anonymous ? nil : params[:reply][:author_name],
      anonymous:   anonymous
    )
    render json: {
      id:          reply.id,
      content:     reply.content,
      author_name: reply.author_name,
      anonymous:   reply.anonymous?,
      created_at:  reply.created_at.strftime("%d/%m/%Y %H:%M")
    }
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
