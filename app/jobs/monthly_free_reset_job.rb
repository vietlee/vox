class MonthlyFreeResetJob < ApplicationJob
  queue_as :default

  # Runs on the 1st of every month via Sidekiq cron.
  # Grants 100 free AI credits to every workspace's active subscription.
  def perform
    monthly_credits = PlanConfig.monthly_free_credits
    count = 0

    Subscription.active.find_each do |sub|
      sub.update_columns(
        credit_balance: sub.credit_balance + monthly_credits,
        max_ai_credits: [sub.max_ai_credits.to_i, monthly_credits].max
      )
      count += 1
    end

    Rails.logger.info("[MonthlyCreditsReset] Granted #{monthly_credits} AI credits to #{count} active subscriptions")
  end
end
