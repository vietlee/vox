class CreateLearnerNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_notifications do |t|
      t.references :learner, null: false, foreign_key: true
      t.string  :title, null: false
      t.text    :body
      t.string  :notification_type, null: false, default: "general"
      t.boolean :read, null: false, default: false
      t.string  :action_url
      t.timestamps
    end
    add_index :learner_notifications, [:learner_id, :read]
  end
end
