class CreatePlanConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :plan_configs do |t|
      t.string  :plan_key,     null: false
      t.string  :display_name, null: false
      t.integer :price_vnd,    null: false, default: 0
      t.string  :billing_cycle, default: "month"
      t.jsonb   :limits,   null: false, default: {}
      t.jsonb   :features, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :plan_configs, :plan_key, unique: true
  end
end
