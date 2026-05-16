class SubscriptionExpiryReminderJob < ApplicationJob
  queue_as :default

  # Runs daily via Sidekiq cron. Sends renewal reminder emails for subscriptions
  # expiring in 7 days, and marks expired subscriptions accordingly.
  def perform
    check_expiring
    mark_expired
  end

  private

  def check_expiring
    Subscription.active.where(auto_renew: true)
                .where(ends_at: Time.current..7.days.from_now)
                .includes(:workspace)
                .each do |sub|
      admin = sub.workspace&.users&.find_by(role: :admin)
      next unless admin

      SubscriptionMailer.renewal_reminder(sub, admin).deliver_later
    end
  end

  def mark_expired
    Subscription.active.where("ends_at < ?", Time.current).update_all(status: :expired)
  end
end
