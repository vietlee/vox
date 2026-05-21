class Admin::VotesController < Admin::BaseController
  before_action :set_vote, only: [:show, :edit, :update, :destroy, :open, :close, :results, :present, :share, :ai_insight]

  def index
    direction = params[:sort] == "asc" ? :asc : :desc
    @sort     = params[:sort] == "asc" ? "asc" : "desc"
    votes     = current_workspace.votes.order(created_at: direction)
    votes     = votes.where(status: params[:status]) if params[:status].present?
    votes     = votes.where(vote_type: params[:type]) if params[:type].present?
    @pagy, @votes = pagy(votes, items: 15)
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
      audit_log("vote.create", resource: @vote)
      redirect_to edit_vote_path(@vote), notice: t("votes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    unless @vote.draft?
      redirect_to edit_vote_path(@vote), alert: t("votes_errors.draft_only_edit")
      return
    end
    if @vote.update(vote_params)
      redirect_to edit_vote_path(@vote), notice: t("votes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @vote.active?
      respond_to do |format|
        format.json { render json: { error: t("votes_errors.cannot_delete_active") }, status: :forbidden }
        format.html { redirect_to votes_path, alert: t("votes_errors.cannot_delete_active") }
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
    if @vote.closed?
      respond_to do |format|
        format.html { redirect_to edit_vote_path(@vote), alert: t("votes_errors.cannot_reopen_closed") }
        format.json { render json: { error: t("votes_errors.cannot_reopen_closed") }, status: :forbidden }
      end
      return
    end
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
    return unless require_ai_feature!(:ai_analysis)
    return unless require_credits!(2)

    current_workspace.active_subscription&.deduct_credits!(2)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "post_vote_insight", resource_type: "Vote", resource_id: @vote.id, credits_cost: 2)
    AiPostVoteInsightJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  private

  def set_vote
    @vote = current_workspace.votes.find(params[:id])
  end

  def vote_params
    params.require(:vote).permit(:title, :vote_type, :identity_mode, :countdown_seconds, :show_results_live, :allow_multiple_votes, :login_providers)
  end

  def build_vote_options
    options_params = params[:vote][:vote_options_attributes]
    return unless options_params
    options_params.values.each_with_index do |opt, idx|
      label = opt[:label].to_s.strip
      next if label.blank?
      @vote.vote_options.create(label: label, position: idx)
    end
  end
end
