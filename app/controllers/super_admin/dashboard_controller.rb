class SuperAdmin::DashboardController < SuperAdmin::BaseController
  def index
    @workspaces_count  = Workspace.count
    @users_count       = User.count
    @surveys_count     = Survey.count
    @votes_count       = Vote.count
    @recent_workspaces = Workspace.order(created_at: :desc).limit(10)
  end
end
