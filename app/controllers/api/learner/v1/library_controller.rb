class Api::Learner::V1::LibraryController < Api::Learner::V1::BaseController
  def index
    q = params[:q].to_s.strip

    quiz_scope = current_learner.quiz_assignments.includes(:quiz_set).order(created_at: :desc)
    fc_scope   = current_learner.flashcard_assignments.includes(:flashcard_deck).order(created_at: :desc)
    path_scope = current_learner.learning_path_assignments.includes(:learning_path).order(created_at: :desc)

    if q.present?
      quiz_scope = quiz_scope.joins(:quiz_set).where("quiz_sets.title ILIKE ?", "%#{q}%")
      fc_scope   = fc_scope.joins(:flashcard_deck).where("flashcard_decks.title ILIKE ?", "%#{q}%")
      path_scope = path_scope.joins(:learning_path).where("learning_paths.title ILIKE ?", "%#{q}%")
    end

    render json: {
      quiz_assignments: quiz_scope.map { |a|
        {
          token: a.token,
          title: a.quiz_set.title,
          status: a.status,
          progress: a.progress_pct,
          created_at: a.created_at
        }
      },
      flashcard_assignments: fc_scope.map { |a|
        {
          token: a.token,
          title: a.flashcard_deck.title,
          status: a.status,
          progress: a.progress_pct,
          cards_reviewed: a.cards_reviewed,
          total_cards: a.flashcard_deck.card_count
        }
      },
      path_assignments: path_scope.map { |a|
        {
          token: a.token,
          title: a.learning_path.title,
          status: a.status,
          progress: a.progress_pct,
          due_date: a.due_date
        }
      },
      search_query: q
    }
  end
end
