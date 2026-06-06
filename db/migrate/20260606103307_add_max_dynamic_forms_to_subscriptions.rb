class AddMaxDynamicFormsToSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :subscriptions, :max_dynamic_forms, :integer
    # Set defaults based on current plan
    execute <<~SQL
      UPDATE subscriptions SET max_dynamic_forms =
        CASE plan
          WHEN 0 THEN 3    -- free
          WHEN 1 THEN 10   -- pro
          WHEN 2 THEN NULL -- enterprise (unlimited)
          ELSE 3
        END
    SQL
  end
end
