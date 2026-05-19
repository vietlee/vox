class Participate::VotesController < Participate::BaseController
  before_action :set_vote

  def show
    unless @vote.active?
      render :closed and return
    end
    @options = @vote.vote_options
    @already_voted = !@vote.allow_multiple_votes? &&
                     @vote.vote_responses.exists?(respondent_token: respondent_token)
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
      workspace: @vote.workspace,
      respondent_token: respondent_token,
      respondent_email: params[:respondent_email].presence,
      selected_option_ids: Array(params[:option_ids]).map(&:to_i),
      text_value: params[:text_value],
      ranking_order: params[:ranking_order] || []
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
    @results   = @vote.results_by_option
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
    @vote = Vote.find_by!(slug: params[:slug])
    @workspace = @vote.workspace
  end
end
