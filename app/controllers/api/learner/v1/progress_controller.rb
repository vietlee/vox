class Api::Learner::V1::ProgressController < Api::Learner::V1::BaseController
  def index
    l = current_learner

    days = 14
    stats = l.learner_daily_stats
             .where("day >= ?", (days - 1).days.ago.to_date)
             .index_by(&:day)
    daily = (0...days).map do |i|
      d = (days - 1 - i).days.ago.to_date
      s = stats[d]
      { date: d.to_s, xp: s&.xp.to_i, activities: s&.activities.to_i }
    end
    max_daily_xp = [daily.map { |x| x[:xp] }.max, 1].max

    total_xp       = l.xp
    current_streak = l.current_streak
    longest_streak = l.longest_streak
    lv             = level_for(l.xp)
    xp_into_level, xp_for_next = level_progress(l.xp)

    attempts = QuizAttempt
               .where(participant_email: l.email)
               .where.not(submitted_at: nil)
               .includes(:quiz_set)
               .order(:submitted_at)
    quiz_scores = attempts.last(8).map do |a|
      { title: a.quiz_set&.title.to_s.truncate(24), score: a.score_pct, at: a.submitted_at }
    end

    quizzes_done    = l.quiz_assignments.completed.count
    flashcards_done = l.flashcard_assignments.completed.count
    cards_reviewed  = l.flashcard_assignments.sum(:cards_reviewed)

    badges = l.learner_badges.order(:earned_at).map do |b|
      info = b.info
      { key: b.key, icon: info[:icon], title: info[:title], earned_at: b.earned_at }
    end

    workspace_ids = LearnerFolder.joins(:learner_folder_members)
      .where(learner_folder_members: { learner_id: l.id })
      .pluck(:workspace_id).uniq

    if workspace_ids.any?
      peer_ids = LearnerFolder.where(workspace_id: workspace_ids)
        .joins(:learner_folder_members)
        .pluck("learner_folder_members.learner_id").uniq
      leaderboard_records = Learner.where(id: peer_ids).order(xp: :desc).limit(20)
        .select(:id, :name, :email, :xp, :current_streak)
      leaderboard = leaderboard_records.map do |lb|
        { id: lb.id, name: lb.name, xp: lb.xp, current_streak: lb.current_streak,
          is_me: lb.id == l.id }
      end
      my_rank = leaderboard_records.index { |lb| lb.id == l.id }&.then { |i| i + 1 }
    else
      leaderboard = []
      my_rank = nil
    end

    render json: {
      total_xp: total_xp,
      current_streak: current_streak,
      longest_streak: longest_streak,
      level: lv,
      xp_into_level: xp_into_level,
      xp_for_next: xp_for_next,
      quizzes_done: quizzes_done,
      flashcards_done: flashcards_done,
      cards_reviewed: cards_reviewed,
      daily_xp: daily,
      max_daily_xp: max_daily_xp,
      quiz_scores: quiz_scores,
      badges: badges,
      leaderboard: leaderboard,
      my_rank: my_rank
    }
  end

  private

  def level_for(xp)
    lvl = 1
    lvl += 1 while xp >= threshold(lvl + 1)
    lvl
  end

  def threshold(level) = 50 * (level - 1) * level

  def level_progress(xp)
    lvl  = level_for(xp)
    base = threshold(lvl)
    nxt  = threshold(lvl + 1)
    [xp - base, nxt - base]
  end
end
