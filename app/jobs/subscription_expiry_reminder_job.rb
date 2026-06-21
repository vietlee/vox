class SubscriptionExpiryReminderJob < ApplicationJob
  queue_as :default

  def perform
    # No-op — all features are free, no paid plans to expire
  end
end
