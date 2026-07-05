# Central place to award XP, update daily activity, and maintain streaks.
#
#   LearnerGamification.record!(learner, :quiz_complete, xp: 20)
#
# Returns a hash describing what changed (for optional UI feedback).
class LearnerGamification
  XP = {
    quiz_complete:      20,
    flashcard_session:  10,
    flashcard_card:      1,
    tutor_chat:          2,
    speaking_turn:       3,
    plan_item:          15,
    study_plan_done:    50
  }.freeze

  def self.record!(learner, action, xp: nil, count_activity: true)
    amount = xp || XP[action] || 0
    new(learner).record!(amount, count_activity: count_activity)
  end

  def initialize(learner)
    @learner = learner
  end

  # Awards XP, bumps today's activity counter, and updates streak.
  def record!(amount, count_activity: true)
    today = Date.current
    prev_streak = @learner.current_streak

    LearnerDailyStat.transaction do
      stat = LearnerDailyStat.lock.find_or_create_by!(learner_id: @learner.id, day: today)
      stat.increment!(:xp, amount) if amount > 0
      stat.increment!(:activities, 1) if count_activity

      update_streak!(today)
      @learner.increment!(:xp, amount) if amount > 0
    end

    {
      xp_gained:       amount,
      total_xp:        @learner.reload.xp,
      current_streak:  @learner.current_streak,
      streak_extended: @learner.current_streak > prev_streak,
      goal_met:        goal_met_today?,
      daily_goal:      @learner.daily_goal,
      activities_today: activities_today
    }
  end

  def activities_today
    LearnerDailyStat.find_by(learner_id: @learner.id, day: Date.current)&.activities.to_i
  end

  def goal_met_today?
    activities_today >= @learner.daily_goal
  end

  private

  def update_streak!(today)
    last = @learner.last_active_on
    return if last == today # already counted today

    new_streak =
      if last == today - 1 then @learner.current_streak + 1
      else 1 # first activity ever, or streak broken
      end

    longest = [@learner.longest_streak, new_streak].max
    @learner.update_columns(
      current_streak: new_streak,
      longest_streak: longest,
      last_active_on: today
    )
  end
end
