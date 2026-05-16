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

    vote_response = @vote.vote_responses.build(
      workspace: @vote.workspace,
      respondent_token: respondent_token,
      respondent_email: params[:respondent_email],
      selected_option_ids: Array(params[:option_ids]).map(&:to_i),
      text_value: params[:text_value],
      ranking_order: params[:ranking_order] || []
    )

    if vote_response.save
      render json: { success: true, results: @vote.reload.results_by_option }
    elsif vote_response.errors.where(:base, :already_voted).any?
      render json: { error: "already_voted", message: "Bạn đã vote rồi, không thể vote lại." }, status: :unprocessable_entity
    else
      render json: { error: "failed", message: "Không thể gửi vote." }, status: :unprocessable_entity
    end
  end

  def results
    @results   = @vote.results_by_option
    @ai_insight = AiJob.done.where(job_type: "post_vote_insight", resource_type: "Vote", resource_id: @vote.id).last&.output_data
    respond_to do |format|
      format.html
      format.json { render json: { results: @results, participant_count: @vote.participant_count } }
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
