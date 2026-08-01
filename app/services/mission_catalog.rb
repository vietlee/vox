# Central registry of credit-earning missions. The server owns the reward
# amounts, targets and progress logic; the app localizes titles/icons by key.
module MissionCatalog
  module_function

  # type: :daily resets every day; :milestone is claimable once, ever.
  MISSIONS = [
    # ── Daily ──────────────────────────────────────────────────────────────
    { key: "daily_study_1", type: :daily,     target: 1,   reward: 2  },
    { key: "daily_study_3", type: :daily,     target: 3,   reward: 5  },
    { key: "daily_xp_50",   type: :daily,     target: 50,  reward: 5  },
    # ── Milestones ─────────────────────────────────────────────────────────
    { key: "first_study",   type: :milestone, target: 1,   reward: 5  },
    { key: "first_quiz",    type: :milestone, target: 1,   reward: 10 },
    { key: "quiz_10",       type: :milestone, target: 10,  reward: 20 },
    { key: "review_100",    type: :milestone, target: 100, reward: 20 },
    { key: "streak_7",      type: :milestone, target: 7,   reward: 20 },
    { key: "streak_30",     type: :milestone, target: 30,  reward: 50 },
    { key: "invite_3",      type: :milestone, target: 3,   reward: 30 },
  ].freeze

  def all
    MISSIONS
  end

  def find(key)
    MISSIONS.find { |m| m[:key] == key.to_s }
  end

  def period_for(mission)
    mission[:type] == :daily ? Date.current.to_s : "once"
  end

  # Current progress toward a mission, capped at its target.
  def progress_for(mission, learner)
    [raw_progress(mission[:key], learner).to_i, mission[:target]].min
  end

  def raw_progress(key, l)
    case key
    when "daily_study_1", "daily_study_3" then today_stat(l)&.activities.to_i
    when "daily_xp_50"                    then today_stat(l)&.xp.to_i
    when "first_study"                    then l.learner_daily_stats.sum(:activities)
    when "first_quiz"                     then QuizSet.where(learner_id: l.id).count
    when "quiz_10"                        then l.quiz_assignments.completed.count
    when "review_100"                     then l.flashcard_assignments.sum(:cards_reviewed)
    when "streak_7", "streak_30"          then l.longest_streak
    when "invite_3"                       then l.referrals.where.not(referral_rewarded_at: nil).count
    else 0
    end
  end

  def today_stat(l)
    l.learner_daily_stats.find_by(day: Date.current)
  end
end
