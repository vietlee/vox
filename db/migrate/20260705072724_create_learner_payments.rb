class CreateLearnerPayments < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_payments do |t|
      t.references :learner, null: false, foreign_key: true
      t.integer :amount_cents
      t.string :currency
      t.integer :status
      t.string :gateway
      t.bigint :payos_order_code
      t.string :payment_link_id
      t.string :invoice_number
      t.integer :credits_amount

      t.timestamps
    end
  end
end
