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
    @supporters_count = @workspace.workspace_memberships.active.where(role: :supporter).count

    # Recent activity
    @active_surveys   = @workspace.surveys.active.order(created_at: :desc).limit(5)
    @active_votes     = @workspace.votes.active.order(created_at: :desc).limit(5)
    @recent_feedbacks = Feedback.joins(:workspace).where(workspace: @workspace).order(created_at: :desc).limit(8)
    @recent_ai_jobs   = @workspace.ai_jobs.done.order(completed_at: :desc).limit(3)

    # AI credits
    @ai_credit_pct = @subscription&.credit_percentage || 0

    # Onboarding checklist — shown to new workspaces
    @onboarding = build_onboarding_checklist
  end

  private

  def build_onboarding_checklist
    w = @workspace
    items = [
      { key: :workspace_created,  done: true,                                   label: "onboarding.steps.workspace_created",  url: nil },
      { key: :create_survey,      done: w.surveys.exists?,                       label: "onboarding.steps.create_survey",      url: Rails.application.routes.url_helpers.new_survey_path },
      { key: :create_vote,        done: w.votes.exists?,                         label: "onboarding.steps.create_vote",        url: Rails.application.routes.url_helpers.new_vote_path },
      { key: :create_feedback,    done: w.feedback_boards.exists?,               label: "onboarding.steps.create_feedback",    url: Rails.application.routes.url_helpers.new_feedback_board_path },
      { key: :invite_member,      done: w.workspace_memberships.exists?,          label: "onboarding.steps.invite_member",      url: Rails.application.routes.url_helpers.new_member_path },
    ]
    done_count = items.count { |i| i[:done] }
    { items: items, done: done_count, total: items.size, complete: done_count == items.size }
  end
end
