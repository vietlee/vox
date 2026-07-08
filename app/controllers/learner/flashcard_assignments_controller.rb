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
    total    = @assignment.flashcard_deck.flashcards.count
    mastered = params[:mastered].in?([true, "true", 1, "1"])
    rating   = params[:rating].to_s  # "again"|"hard"|"good"|"easy"

    save_srs_review(params[:flashcard_id].to_i, rating) if params[:flashcard_id].present?

    gam_result = nil
    if mastered
      was_completed = @assignment.completed?
      new_count = [@assignment.cards_reviewed + 1, total].min
      if new_count >= total
        @assignment.update!(cards_reviewed: new_count, status: :completed, completed_at: Time.current)
        gam_result = LearnerGamification.record!(current_learner, :flashcard_session, count_activity: !was_completed) unless was_completed
      else
        @assignment.update_columns(cards_reviewed: new_count)
        gam_result = LearnerGamification.record!(current_learner, :flashcard_card, count_activity: new_count == 1)
      end
    end

    new_badges = (gam_result&.dig(:new_badges) || []).map do |b|
      { icon: b.info[:icon], title: b.info[:title], desc: b.info[:desc] }
    end

    review_record = FlashcardReview.find_by(flashcard_id: params[:flashcard_id], learner_id: current_learner.id)
    render json: { ok: true, completed: @assignment.completed?,
                   progress: @assignment.cards_reviewed, total: total,
                   next_review_at: review_record&.next_review_at,
                   new_badges: new_badges }
  end

  private

  def save_srs_review(flashcard_id, rating_str)
    rating_int = { "again" => 0, "hard" => 1, "good" => 2, "easy" => 3 }[rating_str]
    return unless rating_int

    review = FlashcardReview.for_learner_card(current_learner.id, flashcard_id)
    current_ease     = review.ease_factor || 2.5
    current_interval = review.interval_days || 1

    _unused, new_ease, new_interval = Flashcard.next_interval(rating_int, current_ease, current_interval)

    review.assign_attributes(
      rating:         rating_int,
      ease_factor:    [1.3, new_ease.to_f].max,
      interval_days:  [new_interval.to_i, 1].max,
      next_review_at: new_interval.to_i.days.from_now
    )
    review.save!
  rescue => e
    Rails.logger.warn("SRS save error for card #{flashcard_id}: #{e.message}")
  end

  def set_assignment
    @assignment = current_learner.flashcard_assignments.find_by!(token: params[:token])
  end
end
