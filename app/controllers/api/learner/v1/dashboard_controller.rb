class Api::Learner::V1::DashboardController < Api::Learner::V1::BaseController
  CONTINUE_LIMIT = 5

  def index
    @quiz_count      = current_learner.quiz_assignments.count
    @flashcard_count = current_learner.flashcard_assignments.count
    @path_count      = current_learner.learning_path_assignments.count

    load_pending_assignments

    continue  = continue_items.first(CONTINUE_LIMIT)
    active_total = continue_items.size

    gam = LearnerGamification.new(current_learner)
    streak           = current_learner.current_streak
    xp               = current_learner.xp
    daily_goal       = current_learner.daily_goal
    activities_today = gam.activities_today
    goal_met         = gam.goal_met_today?

    daily_challenge = current_learner.learner_daily_challenges.find_by(challenge_date: Date.current)

    srs_decks = srs_due_decks

    render json: {
      learner: learner_json(current_learner),
      streak: streak,
      xp: xp,
      daily_goal: daily_goal,
      activities_today: activities_today,
      goal_met: goal_met,
      continue: continue,
      active_total: active_total,
      daily_challenge: daily_challenge ? {
        id: daily_challenge.id,
        completed: daily_challenge.completed,
        score_pct: daily_challenge.completed ? daily_challenge.score_pct : nil
      } : nil,
      srs_due_decks: srs_decks,
      quiz_count: @quiz_count,
      flashcard_count: @flashcard_count,
      path_count: @path_count
    }
  end

  private

  def load_pending_assignments
    @quiz_assignments      = current_learner.quiz_assignments.includes(:quiz_set)
                               .where(status: [:pending, :in_progress]).order(created_at: :desc)
    @flashcard_assignments = current_learner.flashcard_assignments.includes(:flashcard_deck)
                               .where(status: [:pending, :in_progress]).order(created_at: :desc)
    @path_assignments      = current_learner.learning_path_assignments.includes(:learning_path)
                               .where(status: :active).order(created_at: :desc)
  end

  def continue_items
    @continue_items ||= begin
      far = 100.years.from_now
      items = []

      @quiz_assignments.each do |a|
        due = a.due_at
        items << {
          type: "quiz",
          title: a.quiz_set.title,
          token: a.token,
          cta: a.in_progress? ? "Tiếp tục" : "Bắt đầu",
          progress: a.progress_pct,
          overdue: a.respond_to?(:overdue?) && a.overdue?,
          sort: [due && due < Time.current ? 0 : 1, (due || far).to_i, -a.updated_at.to_i]
        }
      end

      @flashcard_assignments.each do |a|
        items << {
          type: "flashcard",
          title: a.flashcard_deck.title,
          token: a.token,
          cta: a.cards_reviewed.to_i > 0 ? "Tiếp tục" : "Học ngay",
          progress: a.progress_pct,
          overdue: false,
          sort: [1, far.to_i, -a.updated_at.to_i]
        }
      end

      @path_assignments.each do |a|
        due = a.due_date&.to_time
        items << {
          type: "path",
          title: a.learning_path.title,
          token: a.token,
          cta: "Tiếp tục",
          progress: a.progress_pct,
          overdue: due && due < Time.current,
          sort: [due && due < Time.current ? 0 : 1, (due || far).to_i, -a.updated_at.to_i]
        }
      end

      items.sort_by { |i| i[:sort] }.map { |i| i.except(:sort) }
    end
  end

  def srs_due_decks
    due_by_deck = FlashcardReview.joins(:flashcard)
      .where(learner_id: current_learner.id)
      .where('flashcard_reviews.next_review_at <= ?', Time.current)
      .group('flashcards.flashcard_deck_id')
      .count
    return [] if due_by_deck.empty?

    assignments_by_deck = current_learner.flashcard_assignments
      .includes(:flashcard_deck)
      .where(flashcard_deck_id: due_by_deck.keys)
      .index_by(&:flashcard_deck_id)

    due_by_deck.filter_map do |deck_id, count|
      a = assignments_by_deck[deck_id]
      next unless a
      { title: a.flashcard_deck.title, due_count: count, token: a.token }
    end
  end
end
