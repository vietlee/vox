class Participate::VotesController < Participate::BaseController
  before_action :set_vote
  before_action :enforce_login_required!, only: [:show, :submit]

  def show
    unless @vote.active?
      render :closed and return
    end
    @options = @vote.vote_options.includes(:image_attachment, :image_blob)
    @already_voted = !@vote.allow_multiple_votes? && already_voted?
    @seconds_remaining = @vote.seconds_remaining
  end

  def submit
    unless @vote.active?
      render json: { error: "Vote is closed" }, status: :forbidden
      return
    end

    if @vote.email_required? && params[:respondent_email].blank?
      render json: { error: "email_required", message: t("participate.vote.email_required_msg") }, status: :unprocessable_entity
      return
    end

    vote_response = @vote.vote_responses.build(
      workspace:           @vote.workspace,
      respondent_token:    respondent_token,
      respondent_email:    current_user&.email || params[:respondent_email].presence,
      user_id:             current_user&.id,
      fingerprint:         params[:fingerprint].presence&.slice(0, 64),
      selected_option_ids: Array(params[:option_ids]).map(&:to_i),
      text_value:          params[:text_value],
      ranking_order:       params[:ranking_order] || []
    )

    if vote_response.save
      render json: { success: true, results: @vote.reload.results_by_option }
    elsif vote_response.errors.where(:base, :already_voted).any?
      render json: { error: "already_voted", message: t("participate.vote.already_voted_msg") }, status: :unprocessable_entity
    else
      render json: { error: "failed", message: t("participate.vote.submit_failed") }, status: :unprocessable_entity
    end
  end

  def results
    @results    = @vote.results_by_option
    @ai_insight = AiJob.done.where(job_type: "post_vote_insight", resource_type: "Vote", resource_id: @vote.id).last&.output_data
    respond_to do |format|
      format.html
      format.json { render json: { results: @results, participant_count: @vote.participant_count, ai_insight: @ai_insight } }
    end
  end

  def present
    @readonly = params[:readonly].present?
    render layout: "presenter"
  end

  private

  def set_vote
    @vote      = Vote.find_by!(slug: params[:slug])
    @workspace = @vote.workspace
  end

  def enforce_login_required!
    return unless @vote.login_required?
    # Workspace members (admin/supporter/super_admin) always bypass — they're already verified
    return if current_user&.workspace_member?
    # Check that the logged-in user's SSO provider matches what the vote requires
    return if sso_provider_satisfied?

    session[:omniauth_return_to] = request.url
    session["user_return_to"]    = request.url
    render :login_required, status: :ok
  end

  # Returns true if current_user is logged in via an SSO provider
  # that satisfies the vote's login_providers requirement.
  def already_voted?
    # Logged-in user: check by user_id (covers all devices/browsers)
    return @vote.vote_responses.exists?(user_id: current_user.id) if current_user.present?
    # Anonymous: cookie token (fingerprint checked client-side via /check_voted endpoint)
    respondent_token.present? && @vote.vote_responses.exists?(respondent_token: respondent_token)
  end

  def sso_provider_satisfied?
    return false unless current_user.present?
    return false if current_user.provider.blank?   # email/password user — must re-auth via SSO

    case @vote.effective_login_providers
    when "google"    then current_user.provider == "google_oauth2"
    when "microsoft" then current_user.provider == "entra_id"
    when "both"      then current_user.provider.in?(%w[google_oauth2 entra_id])
    else false
    end
  end
end
