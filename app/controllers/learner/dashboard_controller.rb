class Learner::DashboardController < Learner::BaseController
  def index
    @quiz_assignments = current_learner.quiz_assignments
                          .includes(:quiz_set)
                          .order(created_at: :desc)

    @flashcard_assignments = current_learner.flashcard_assignments
                               .includes(:flashcard_deck)
                               .order(created_at: :desc)

    @path_assignments = current_learner.learning_path_assignments
                          .includes(:learning_path)
                          .order(created_at: :desc)

    @pending_count = @quiz_assignments.pending.count +
                     @flashcard_assignments.pending.count +
                     @path_assignments.active.count
  end
end
