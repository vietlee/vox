class CreatePayments < ActiveRecord::Migration[7.2]
  def change
    create_table :payments do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :subscription,   null: false, foreign_key: true
      t.integer     :amount_cents,   null: false
      t.string      :currency,       default: "VND"
      t.integer     :status,         null: false, default: 0
      t.string      :gateway,        null: false
      t.string      :gateway_transaction_id
      t.string      :invoice_number
      t.jsonb       :gateway_response, default: {}
      t.datetime    :paid_at
      t.timestamps
    end
    add_index :payments, :status
    add_index :payments, :gateway
  end
end
