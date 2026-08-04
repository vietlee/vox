class CreateLearnerIapPurchases < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_iap_purchases do |t|
      t.references :learner, null: false, foreign_key: true
      t.string  :platform,       null: false, default: "apple"
      t.string  :product_id,     null: false
      t.string  :transaction_id, null: false
      t.integer :credits,        null: false, default: 0
      t.string  :status,         null: false, default: "granted"
      t.timestamps
    end
    add_index :learner_iap_purchases, [:platform, :transaction_id], unique: true
  end
end
