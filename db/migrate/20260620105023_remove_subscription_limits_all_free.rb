class RemoveSubscriptionLimitsAllFree < ActiveRecord::Migration[7.2]
  def up
    # All features are now free — remove limits on all subscriptions
    Subscription.update_all(
      max_surveys: nil,
      max_votes: nil,
      max_feedbacks: nil,
      max_supporters: nil,
      max_dynamic_forms: nil,
      plan: 0, # free
      status: 0 # active
    )

    # Grant 100 AI credits to subscriptions that have 0
    Subscription.where("credit_balance < ?", 100).update_all(
      credit_balance: 100,
      max_ai_credits: 100
    )
  end

  def down
    # No-op — can't reverse without knowing original plan data
  end
end
