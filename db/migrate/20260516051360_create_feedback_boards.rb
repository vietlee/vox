class CreateFeedbackBoards < ActiveRecord::Migration[7.2]
  def change
    create_table :feedback_boards do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :user,           null: false, foreign_key: true
      t.string      :title,          null: false
      t.text        :description
      t.integer     :status,         null: false, default: 0
      t.integer     :identity_mode,  null: false, default: 0
      t.boolean     :auto_moderation, default: true
      t.boolean     :manual_approval, default: false
      t.boolean     :allow_replies,  default: true
      t.boolean     :allow_upvotes,  default: true
      t.string      :slug
      t.jsonb       :tags,           default: []
      t.timestamps
    end
    add_index :feedback_boards, :slug, unique: true
    add_index :feedback_boards, :status
  end
end
