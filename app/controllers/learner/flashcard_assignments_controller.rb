class Learner::FlashcardAssignmentsController < Learner::BaseController
  before_action :set_assignment

  def show; end

  def study
    @assignment.in_progress! if @assignment.pending?
    @deck  = @assignment.flashcard_deck
    @cards = @deck.flashcards.order(:position)
  end

  def review
    card = Flashcard.find(params[:flashcard_id])
    FlashcardReview.create!(
      flashcard: card,
      user_id:   0, # placeholder; learner reviews stored separately
      rating:    params[:rating]
    )

    remaining = @assignment.flashcard_deck.flashcards
                  .where.not(id: FlashcardReview.where(user_id: 0, flashcard: @assignment.flashcard_deck.flashcards).select(:flashcard_id))
                  .count

    if remaining == 0
      @assignment.completed!
      @assignment.update!(completed_at: Time.current)
    end

    render json: { ok: true, completed: @assignment.completed? }
  end

  private

  def set_assignment
    @assignment = current_learner.flashcard_assignments.find_by!(token: params[:token])
  end
end
