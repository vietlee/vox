class CreateLearnerPushSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_push_subscriptions do |t|
      t.references :learner, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh_key
      t.string :auth_key
      t.string :reminder_hour, default: "20"
      t.boolean :active, default: true
      t.timestamps
    end
    add_index :learner_push_subscriptions, :endpoint, unique: true
  end
end
