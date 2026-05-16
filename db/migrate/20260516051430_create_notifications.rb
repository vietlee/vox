class CreateNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :notifications do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :user,           null: false, foreign_key: true
      t.string      :notification_type, null: false
      t.string      :title,          null: false
      t.text        :body
      t.boolean     :read,           default: false
      t.string      :resource_type
      t.integer     :resource_id
      t.jsonb       :metadata,       default: {}
      t.timestamps
    end
    add_index :notifications, [:user_id, :read]
    add_index :notifications, :created_at
  end
end
