class CreateAddonConfigsAndAddAddonToPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :addon_configs do |t|
      t.string  :name,             null: false
      t.string  :description
      t.string  :addon_type,       null: false, default: "resource_pack"
      t.integer :price_cents,      null: false, default: 0
      t.integer :surveys_bonus,    default: 0
      t.integer :votes_bonus,      default: 0
      t.integer :feedbacks_bonus,  default: 0
      t.integer :ai_credits_bonus, default: 0
      t.boolean :active,           default: true, null: false
      t.integer :sort_order,       default: 0
      t.timestamps
    end

    add_column :payments, :addon_config_id, :bigint
    add_index  :payments, :addon_config_id
  end
end
