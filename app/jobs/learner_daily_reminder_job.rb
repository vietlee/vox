# Sends a daily nudge email to learners who haven't studied today, to protect
# their streak and remind them of pending/overdue work. Runs once per day (evening).
class LearnerDailyReminderJob < ApplicationJob
  queue_as :mailers

  MAX_TASKS = 4

  # Runs every hour (Asia/Ho_Chi_Minh). Sends a PUSH to each subscribed learner
  # at the hour THEY chose, and an evening EMAIL nudge at 20:00.
  def perform
    return unless ENV["LEARNER_DAILY_REMINDER"] != "off"

    today        = Date.current
    current_hour = Time.current.in_time_zone("Asia/Ho_Chi_Minh").hour

    send_hourly_push(today, current_hour)
    send_evening_email(today) if current_hour == 20
  end

  private

  # Push to every learner whose chosen reminder hour matches the current hour.
  # They opted in explicitly, so we nudge as long as they haven't studied today
  # (no streak/pending-task requirement — a plain "come study" reminder).
  def send_hourly_push(_today, current_hour)
    learner_ids = LearnerPushSubscription
                    .where(active: true, reminder_hour: current_hour.to_s)
                    .distinct.pluck(:learner_id)
    return if learner_ids.empty?

    # Fire at the hour the learner explicitly chose — a user-set reminder should
    # always arrive at its time (we do NOT skip learners who were active today;
    # that silently suppressed the reminder for anyone using the app).
    Learner.where(id: learner_ids).find_each do |learner|
      send_push_if_subscribed(learner)
    rescue => e
      Rails.logger.warn("[LearnerDailyReminderJob push] learner #{learner.id}: #{e.message}")
    end
  end

  # Evening email nudge (20:00) — protect streak / surface pending work.
  def send_evening_email(today)
    eligible_learners(today).find_each do |learner|
      next if learner.last_active_on == today
      next unless learner.current_streak >= 1 || self.class.pending_tasks_for(learner).any?

      LearnerMailer.daily_reminder(learner).deliver_later
    rescue => e
      Rails.logger.warn("[LearnerDailyReminderJob email] learner #{learner.id}: #{e.message}")
    end
  end

  def send_push_if_subscribed(learner)
    return unless learner.learner_push_subscriptions.where(active: true).exists?

    streak_msg = learner.current_streak >= 1 ? " Đừng để mất streak #{learner.current_streak} ngày!" : ""
    PushNotificationService.send_to_learner(
      learner,
      title: "⏰ Nhắc học VOX",
      body:  "Đến giờ học rồi!#{streak_msg}",
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
