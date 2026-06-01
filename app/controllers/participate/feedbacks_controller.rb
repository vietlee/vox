class Participate::FeedbacksController < Participate::BaseController
  before_action :set_board

  PER_PAGE = 10

  def show
    unless @board.active?
      render :closed and return
    end
    @feedbacks   = @board.feedbacks.visible.pinned_first.includes(:feedback_replies).limit(PER_PAGE)
    @feedback    = @board.feedbacks.build
    @upvoted_ids = FeedbackUpvote.where(feedback: @feedbacks, voter_token: respondent_token).pluck(:feedback_id).to_set
    @has_more    = @board.feedbacks.visible.count > PER_PAGE
    @reply_default_name = current_user ? current_user.display_name : t("participate.feedback.anonymous")
  end

  def list
    offset   = params[:offset].to_i
    feedbacks = @board.feedbacks.visible.pinned_first.includes(:feedback_replies).offset(offset).limit(PER_PAGE)
    total     = @board.feedbacks.visible.count
    token     = respondent_token
    upvoted   = FeedbackUpvote.where(feedback: feedbacks, voter_token: token).pluck(:feedback_id).to_set

    render json: {
      feedbacks: feedbacks.map { |fb| serialize_feedback(fb, upvoted) },
      has_more:  total > offset + PER_PAGE,
      total:     total
    }
  end

  def submit
    fb_params = params[:feedback] || {}
    @feedback = @board.feedbacks.build(
      workspace:    @board.workspace,
      content:      fb_params[:content],
      author_name:  fb_params[:author_name],
      author_email: fb_params[:email] || fb_params[:author_email],
      anonymous:    fb_params[:anonymous] == "1"
    )
    @feedback.images.attach(fb_params[:images]) if fb_params[:images].present?

    if @feedback.save
      pending     = @board.manual_approval?
      ai_moderate = @board.auto_moderation?
      @feedback.approve! unless pending

      message = if pending
        t("feedbacks.pending_approval")
      elsif ai_moderate
        t("feedbacks.submitted_ai_moderation")
      else
        t("feedbacks.submitted")
      end

      render json: {
        status:      pending ? "pending" : "submitted",
        message:     message,
        feedback:    pending ? nil : serialize_feedback(@feedback, Set.new),
        moderation:  !pending && ai_moderate
      }
    else
      render json: { error: @feedback.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def reply
    unless @board.allow_replies?
      render json: { error: "Replies not allowed" }, status: :forbidden and return
    end
    feedback = @board.feedbacks.visible.find(params[:feedback_id])
    anonymous = params.dig(:reply, :author_name).blank?
    reply = feedback.feedback_replies.create!(
      content:     params.dig(:reply, :content),
      author_name: anonymous ? nil : params.dig(:reply, :author_name),
      anonymous:   anonymous
    )
    reply.images.attach(params.dig(:reply, :images)) if params.dig(:reply, :images).present?
    render json: {
      id:          reply.id,
      content:     reply.content,
      author_name: reply.author_name,
      anonymous:   reply.anonymous?,
      created_at:  reply.created_at.strftime("%d/%m/%Y %H:%M"),
      image_urls:  reply.images.attached? ? reply.images.map { |img| url_for(img) } : []
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

  def serialize_feedback(fb, upvoted_ids)
    {
      id:            fb.id,
      content:       fb.content,
      author_name:   fb.anonymous? || fb.author_name.blank? ? nil : fb.author_name,
      anonymous:     fb.anonymous? || fb.author_name.blank?,
      upvotes_count: fb.upvotes_count,
      upvoted:       upvoted_ids.include?(fb.id),
      pinned:        fb.pinned?,
      implemented:   fb.implemented?,
      allow_replies: @board.allow_replies?,
      replies_count: fb.feedback_replies.size,
      created_at:    I18n.l(fb.created_at, format: :short),
      image_urls:    fb.images.attached? ? fb.images.map { |img| url_for(img) } : []
    }
  end

  def set_board
    @board = FeedbackBoard.find_by!(slug: params[:slug])
    @workspace = @board.workspace
  end
end
