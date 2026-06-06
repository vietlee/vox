class FixProMaxDynamicForms < ActiveRecord::Migration[7.2]
  def change
    # Update Pro subscriptions: 10 → 50
    execute "UPDATE subscriptions SET max_dynamic_forms = 50 WHERE plan = 1"
    # Ensure nil-valued Pro subs also get fixed
    execute "UPDATE subscriptions SET max_dynamic_forms = 50 WHERE plan = 1 AND max_dynamic_forms IS NULL"
  end
end
