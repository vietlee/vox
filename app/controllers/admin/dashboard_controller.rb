class Admin::DashboardController < Admin::BaseController
  def index
    @workspace = current_workspace
    return redirect_to super_admin_root_path if @workspace.nil?
    @subscription = @workspace.active_subscription

    # Stats
    @surveys_count    = @workspace.surveys.count
    @votes_count      = @workspace.votes.count
    @feedbacks_count  = @workspace.feedback_boards.map { |b| b.feedbacks.count }.sum
    @responses_count  = Response.joins(:survey).where(surveys: { workspace_id: @workspace.id }).count

    # Recent activity
    @active_surveys   = @workspace.surveys.active.order(created_at: :desc).limit(5)
    @active_votes     = @workspace.votes.active.order(created_at: :desc).limit(5)
    @recent_feedbacks = Feedback.joins(:workspace).where(workspace: @workspace).order(created_at: :desc).limit(8)
    @recent_ai_jobs   = @workspace.ai_jobs.done.order(completed_at: :desc).limit(3)

    # AI credits
    @ai_credit_pct = @subscription&.credit_percentage || 0
  end
end
