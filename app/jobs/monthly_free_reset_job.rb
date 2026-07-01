class MonthlyFreeResetJob < ApplicationJob
  queue_as :default

  # Runs on the 1st of every month via Sidekiq cron.
  # Grants credits to each OWNER's primary subscription only — users with
  # multiple workspaces still get one budget, not one per workspace.
  def perform
    monthly_credits = PlanConfig.monthly_free_credits
    count = 0

    # Collect the canonical (primary) subscription ID for each owner.
    # A user who owns N workspaces contributes only their oldest workspace's subscription.
    primary_sub_ids = User.where.not(id: nil)
                          .joins(:owned_workspaces)
                          .select("users.id")
                          .distinct
                          .filter_map { |u| u.primary_subscription&.id }
                          .uniq

    # Workspaces with no owner still get credits for the workspace itself.
    ownerless_sub_ids = Workspace.where(owner_id: nil)
                                 .joins(:subscriptions)
                                 .merge(Subscription.active)
                                 .pluck("subscriptions.id")

    all_ids = (primary_sub_ids + ownerless_sub_ids).uniq

    Subscription.active.where(id: all_ids).find_each do |sub|
      sub.update_columns(
        credit_balance: monthly_credits,
        max_ai_credits: monthly_credits
      )
      count += 1
    end

    Rails.logger.info("[MonthlyCreditsReset] Granted #{monthly_credits} AI credits to #{count} primary subscriptions (shared per owner)")
  end
end
