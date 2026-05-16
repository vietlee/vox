class CreateSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :subscriptions do |t|
      t.references :workspace,    null: false, foreign_key: true
      t.integer    :plan,         null: false, default: 0
      t.integer    :status,       null: false, default: 0
      t.datetime   :starts_at
      t.datetime   :ends_at
      t.boolean    :auto_renew,   default: true
      t.integer    :credit_balance,  default: 0
      t.integer    :credit_used,     default: 0
      t.integer    :max_surveys,     default: 3
      t.integer    :max_votes,       default: 3
      t.integer    :max_feedbacks,   default: 10
      t.integer    :max_supporters,  default: 0
      t.integer    :max_ai_credits,  default: 0
      t.integer    :price_cents,     default: 0
      t.string     :currency,        default: "VND"
      t.string     :billing_cycle,   default: "monthly"
      t.jsonb      :features,        default: {}
      t.timestamps
    end
    add_index :subscriptions, :plan
    add_index :subscriptions, :status
  end
end
