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
    expired = Subscription.active.where("ends_at IS NOT NULL AND ends_at < ?", Time.current)
    expired.each do |sub|
      sub.update_columns(status: Subscription.statuses[:expired])

      # Downgrade workspace to a new free subscription so it keeps working
      next if sub.free?
      free_limits = PlanConfig.limits_for("free").transform_values { |v| v || 0 }
      sub.workspace.subscriptions.create!(
        plan:           :free,
        status:         :active,
        starts_at:      Time.current,
        ends_at:        nil,
        credit_balance: 0,
        features:       PlanConfig.features_for("free"),
        **free_limits
      )

      admin = sub.workspace.users.find_by(role: :admin)
      SubscriptionMailer.plan_expired(sub, admin).deliver_later if admin
    end
  end
end
