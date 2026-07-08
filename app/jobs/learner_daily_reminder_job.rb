# Sends a daily nudge email to learners who haven't studied today, to protect
# their streak and remind them of pending/overdue work. Runs once per day (evening).
class LearnerDailyReminderJob < ApplicationJob
  queue_as :mailers

  MAX_TASKS = 4

  def perform
    return unless ENV["LEARNER_DAILY_REMINDER"] != "off"

    today = Date.current
    eligible_learners(today).find_each do |learner|
      # Skip if already active today (nothing to nudge)
      next if learner.last_active_on == today
      # Only email if there's a reason: a streak to protect OR pending work
      next unless learner.current_streak >= 1 || self.class.pending_tasks_for(learner).any?

      LearnerMailer.daily_reminder(learner).deliver_later
      send_push_if_subscribed(learner)
    rescue => e
      Rails.logger.warn("[LearnerDailyReminderJob] learner #{learner.id}: #{e.message}")
    end
  end

  private

  def send_push_if_subscribed(learner)
    return unless learner.learner_push_subscriptions.where(active: true).exists?

    streak_msg = learner.current_streak >= 1 ? " Đừng để mất streak #{learner.current_streak} ngày!" : ""
    PushNotificationService.send_to_learner(
      learner,
      title: "⏰ Nhắc học VOX",
      body:  "Bạn chưa học hôm nay.#{streak_msg}",
      url:   "/learner/dashboard"
    )
  end

  public

  # Real, confirmed accounts only (not un-accepted invites).
  def eligible_learners(_today)
    Learner.where.not(confirmed_at: nil).where(password_set: true)
  end

  # Up to MAX_TASKS things the learner still needs to do, urgent first.
  def self.pending_tasks_for(learner)
    tasks = []

    learner.quiz_assignments.includes(:quiz_set).where.not(status: 2).each do |a|
      next unless a.quiz_set
      tasks << {
        label: "Quiz: #{a.quiz_set.title}",
        meta:  a.due_at ? "Hạn #{a.due_at.strftime('%d/%m')}" : nil,
        overdue: a.due_at.present? && a.due_at < Time.current,
        due: a.due_at
      }
    end

    learner.flashcard_assignments.includes(:flashcard_deck).where.not(status: 2).each do |a|
      next unless a.flashcard_deck
      tasks << {
        label: "Flashcard: #{a.flashcard_deck.title}",
        meta:  "#{a.flashcard_deck.flashcards.count} thẻ",
        overdue: false, due: nil
      }
    end

    learner.learning_path_assignments.includes(:learning_path).where.not(status: 2).each do |a|
      next unless a.learning_path
      due = a.due_date
      tasks << {
        label: "Lộ trình: #{a.learning_path.title}",
        meta:  due ? "Hạn #{due.strftime('%d/%m')}" : nil,
        overdue: due.present? && due < Date.current,
        due: due&.to_time
      }
    end

    tasks.sort_by { |t| [t[:overdue] ? 0 : 1, t[:due] || 100.years.from_now] }.first(MAX_TASKS)
  end
end
