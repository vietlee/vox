class Admin::DashboardController < Admin::BaseController
  def index
    @workspace = current_workspace
    return redirect_to super_admin_root_path if @workspace.nil?
    @subscription = @workspace.active_subscription

    # Core stats
    @surveys_count        = @workspace.surveys.count
    @votes_count          = @workspace.votes.count
    @feedbacks_count      = @workspace.feedback_boards.map { |b| b.feedbacks.count }.sum
    @members_count        = @workspace.workspace_memberships.active.count
    @quiz_sets_count      = @workspace.quiz_sets.count
    @learning_paths_count = @workspace.learning_paths.count
    @flashcard_decks_count = @workspace.flashcard_decks.count

    # Recent activity
    @active_surveys    = @workspace.surveys.active.order(created_at: :desc).limit(4)
    @active_votes      = @workspace.votes.active.order(created_at: :desc).limit(3)
    @recent_feedbacks  = Feedback.where(workspace: @workspace).order(created_at: :desc).limit(5)
    @recent_quiz_sets  = @workspace.quiz_sets.order(created_at: :desc).limit(4)
    @recent_learning_paths = @workspace.learning_paths.order(created_at: :desc).limit(3)
  end

end
