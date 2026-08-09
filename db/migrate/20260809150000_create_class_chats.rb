class CreateClassChats < ActiveRecord::Migration[7.2]
  def change
    # One group chat per class (learner_folder). Messages can come from a
    # teacher (User) or a learner (Learner) — hence a polymorphic sender.
    create_table :class_chat_messages do |t|
      t.references :learner_folder, null: false, foreign_key: true
      t.references :sender, polymorphic: true, null: false
      t.text :body, null: false
      t.timestamps
    end
    add_index :class_chat_messages, [:learner_folder_id, :created_at]

    # Per-member read cursor for unread badges. Member is also polymorphic
    # (User or Learner).
    create_table :class_chat_reads do |t|
      t.references :learner_folder, null: false, foreign_key: true
      t.references :member, polymorphic: true, null: false
      t.datetime :last_read_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end
    add_index :class_chat_reads,
              [:learner_folder_id, :member_type, :member_id],
              unique: true, name: "idx_class_chat_reads_unique"
  end
end
