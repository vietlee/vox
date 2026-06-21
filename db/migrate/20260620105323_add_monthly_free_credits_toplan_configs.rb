class AddMonthlyFreeCreditsToplanConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :plan_configs, :monthly_free_credits, :integer, default: 100, null: false

    reversible do |dir|
      dir.up do
        execute "UPDATE plan_configs SET monthly_free_credits = 100"
      end
    end
  end
end
