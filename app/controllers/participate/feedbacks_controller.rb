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

  def verify_pending
    ids = Array(params[:ids]).map(&:to_i).uniq.first(50)
    existing = @board.feedbacks.where(id: ids).pluck(:id).to_set
    render json: { existing: existing.to_a }
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

  # POST /f/:slug/voice — record audio from participant, return transcript text
  # Requires: board.allow_voice_input? AND workspace has :stt feature (Pro+)
  VOICE_MAX_BYTES    = 25.megabytes
  VOICE_SECS_PER_CREDIT = 60   # 1 credit per 60 s audio, min 1

  def voice_transcribe
    # Feature gates
    unless @board.allow_voice_input?
      render json: { error: t("participate.feedback.voice_not_enabled") }, status: :forbidden and return
    end

    sub = @workspace.credit_subscription
    unless sub&.has_feature?(:stt)
      render json: { error: t("participate.feedback.voice_upgrade_required") }, status: :payment_required and return
    end

    blob = params[:audio]
    unless blob.present?
      render json: { error: t("participate.feedback.voice_no_audio") }, status: :unprocessable_entity and return
    end

    if blob.size > VOICE_MAX_BYTES
      render json: { error: t("participate.feedback.voice_too_large") }, status: :unprocessable_entity and return
    end

    # Check at least 1 credit available
    unless sub.enterprise? || sub.credit_balance >= 1
      render json: { error: t("participate.feedback.voice_no_credits") }, status: :payment_required and return
    end

    begin
      service = ElevenLabsService.new
      result  = service.speech_to_text(
        audio_io:      blob.tempfile,
        filename:      blob.original_filename.presence || "recording.webm",
        model:         "scribe_v2",
        language_code: nil,   # auto-detect
        timestamps:    "none",
        diarize:       false
      )

      # Deduct 1 credit (single short recording — typical < 1 min)
      duration_secs = params[:duration_secs].to_f
      credits = duration_secs > 0 ? [(duration_secs / VOICE_SECS_PER_CREDIT.to_f).ceil, 1].max : 1
      sub.deduct_credits!(credits)

      render json: { text: result[:text], language_code: result[:language_code], credits_used: credits }

    rescue ElevenLabsService::Error => e
      Rails.logger.warn "Participate::FeedbacksController#voice_transcribe ElevenLabs error: #{e.message}"
      render json: { error: e.message }, status: :service_unavailable
    rescue => e
      Rails.logger.error "Participate::FeedbacksController#voice_transcribe: #{e.message}"
      render json: { error: t("participate.feedback.voice_error") }, status: :internal_server_error
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
