class Admin::VotesController < Admin::BaseController
  before_action :set_vote, only: [:show, :edit, :update, :destroy, :open, :close, :results, :present, :share, :ai_insight]

  def index
    @pagy, @votes = pagy(current_workspace.votes.order(created_at: :desc), items: 15)
  end

  def show
    @responses = @vote.vote_responses.order(created_at: :desc)
    @option_map = @vote.vote_options.index_by { |o| o.id.to_s }
  end

  def new
    @vote = current_workspace.votes.build
  end

  def create
    @vote = current_workspace.votes.build(vote_params)
    @vote.user = current_user

    if @vote.save
      build_vote_options
      redirect_to edit_vote_path(@vote), notice: t("votes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    unless @vote.draft?
      redirect_to edit_vote_path(@vote), alert: "Chỉ có thể chỉnh sửa vote ở trạng thái Draft."
      return
    end
    if @vote.update(vote_params)
      respond_to do |format|
        format.html { redirect_to edit_vote_path(@vote), notice: t("votes.updated") }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @vote.active?
      respond_to do |format|
        format.json { render json: { error: "Không thể xoá vote đang active." }, status: :forbidden }
        format.html { redirect_to votes_path, alert: "Không thể xoá vote đang active." }
      end
      return
    end
    @vote.destroy
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_to votes_path, notice: t("votes.deleted") }
    end
  end

  def open
    @vote.open!
    audit_log("vote.open", resource: @vote)
    respond_to do |format|
      format.html { redirect_to present_vote_path(@vote) }
      format.json { render json: { status: "active" } }
    end
  end

  def close
    @vote.close!
    audit_log("vote.close", resource: @vote)
    # Trigger AI insight if applicable
    if current_workspace.active_subscription&.has_feature?(:ai_analysis)
      AiPostVoteInsightJob.perform_later(@vote.id)
    end
    respond_to do |format|
      format.html { redirect_to results_vote_path(@vote) }
      format.json { render json: { status: "closed" } }
    end
  end

  def results
    @results = @vote.results_by_option
    @ai_insight = AiJob.done
                       .where(job_type: "post_vote_insight", resource_type: "Vote", resource_id: @vote.id)
                       .last&.output_data
  end

  def present
    render "participate/votes/present", layout: "presenter"
  end

  def share
  end

  def ai_insight
    require_ai_feature!(:ai_analysis)
    require_credits!(2)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "post_vote_insight", resource_type: "Vote", resource_id: @vote.id, credits_cost: 2)
    AiPostVoteInsightJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  private

  def set_vote
    @vote = current_workspace.votes.find(params[:id])
  end

  def vote_params
    params.require(:vote).permit(:title, :vote_type, :identity_mode, :countdown_seconds, :show_results_live, :allow_multiple_votes)
  end

  def build_vote_options
    options_params = params[:vote][:vote_options_attributes]
    return unless options_params
    options_params.values.each_with_index do |opt, idx|
      @vote.vote_options.create!(label: opt[:label], position: idx)
    end
  end
end
