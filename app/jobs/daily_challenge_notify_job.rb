# Each morning, drops an in-app bell notification for active learners who
# haven't done today's daily challenge yet — nudging them toward the free
# credits/XP/streak. Deduped per day; skips learners who already completed it.
class DailyChallengeNotifyJob < ApplicationJob
  queue_as :default

  ACTIVE_WINDOW = 14 # days since last seen

  def perform
    return if ENV["DAILY_CHALLENGE_NOTIFY"] == "off"

    today = Date.current
    url   = "/daily-challenge?d=#{today}"

    Learner.where.not(confirmed_at: nil)
           .where(password_set: true)
           .where("last_seen_at >= ?", ACTIVE_WINDOW.days.ago)
           .find_each do |learner|
      next if LearnerDailyChallenge.exists?(learner_id: learner.id, challenge_date: today, completed: true)
      next if learner.learner_notifications.exists?(action_url: url)

      LearnerNotification.notify_t!(
        learner:   learner,
        title_key: "challenge_title",
        body_key:  "challenge_body",
        action_url: url
      )
    rescue => e
      Rails.logger.warn "[DailyChallengeNotifyJob] learner #{learner.id}: #{e.message}"
    end
  end
end
