class Learner::FlashcardAssignmentsController < Learner::BaseController
  before_action :set_assignment

  def show; end

  def study
    if @assignment.completed?
      @assignment.update_columns(cards_reviewed: 0, status: FlashcardAssignment.statuses[:in_progress], completed_at: nil)
    else
      @assignment.in_progress! if @assignment.pending?
    end
    @deck  = @assignment.flashcard_deck
    @cards = @deck.flashcards.order(:position)
  end

  def review
    total     = @assignment.flashcard_deck.flashcards.count
    mastered  = params[:mastered].in?([true, "true", 1, "1"])

    if mastered
      was_completed = @assignment.completed?
      new_count = [@assignment.cards_reviewed + 1, total].min
      if new_count >= total
        @assignment.update!(cards_reviewed: new_count, status: :completed, completed_at: Time.current)
        # Bonus XP for finishing a whole deck (only first time)
        LearnerGamification.record!(current_learner, :flashcard_session, count_activity: !was_completed) unless was_completed
      else
        @assignment.update_columns(cards_reviewed: new_count)
        # Per-card XP; only counts as a daily activity on the first card of the session
        LearnerGamification.record!(current_learner, :flashcard_card, count_activity: new_count == 1)
      end
    end

    render json: { ok: true, completed: @assignment.completed?,
                   progress: @assignment.cards_reviewed, total: total }
  end

  private

  def set_assignment
    @assignment = current_learner.flashcard_assignments.find_by!(token: params[:token])
  end
end
