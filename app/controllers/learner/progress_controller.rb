class Learner::ProgressController < Learner::BaseController
  def index
    l = current_learner

    # Last 12 weeks of XP for the chart (by day, last 14 days for detail)
    @days = 14
    stats = l.learner_daily_stats
             .where("day >= ?", (@days - 1).days.ago.to_date)
             .index_by(&:day)
    @daily = (0...@days).map do |i|
      d = (@days - 1 - i).days.ago.to_date
      s = stats[d]
      { date: d, xp: s&.xp.to_i, activities: s&.activities.to_i }
    end
    @max_daily_xp = [@daily.map { |x| x[:xp] }.max, 1].max

    # Totals
    @total_xp        = l.xp
    @current_streak  = l.current_streak
    @longest_streak  = l.longest_streak
    @level           = level_for(l.xp)
    @xp_into_level, @xp_for_next = level_progress(l.xp)

    # Quiz score trend — score lives on QuizAttempt (matched by email), not QuizAssignment
    attempts = QuizAttempt
               .where(participant_email: l.email)
               .where.not(submitted_at: nil)
               .includes(:quiz_set)
               .order(:submitted_at)
    @quiz_scores = attempts.last(8).map do |a|
      { title: a.quiz_set&.title.to_s.truncate(24), score: a.score_pct, at: a.submitted_at }
    end

    # Counts
    @quizzes_done    = l.quiz_assignments.completed.count
    @flashcards_done = l.flashcard_assignments.completed.count
    @cards_reviewed  = l.flashcard_assignments.sum(:cards_reviewed)

    # Weakest quizzes (below passing) → improvement targets; latest attempt per quiz
    @weak = attempts.to_a.reverse.uniq(&:quiz_set_id)
                    .select { |a| a.quiz_set && !a.passed? }
                    .first(3)

    # Badges
    @badges = l.learner_badges.order(:earned_at)
    @badge_keys_earned = @badges.pluck(:key).to_set
  end

  private

  # Level curve: level n needs 100 * n * (n+1) / 2 total XP (triangular)
  def level_for(xp)
    lvl = 1
    lvl += 1 while xp >= threshold(lvl + 1)
    lvl
  end

  def threshold(level) = 50 * (level - 1) * level # XP needed to REACH `level`

  def level_progress(xp)
    lvl  = level_for(xp)
    base = threshold(lvl)
    nxt  = threshold(lvl + 1)
    [xp - base, nxt - base]
  end

  helper_method :level_for
end
