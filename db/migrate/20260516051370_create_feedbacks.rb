class CreateFeedbacks < ActiveRecord::Migration[7.2]
  def change
    create_table :feedbacks do |t|
      t.references  :feedback_board, null: false, foreign_key: true
      t.references  :workspace,      null: false, foreign_key: true
      t.text        :content,        null: false
      t.string      :author_name
      t.string      :author_email
      t.boolean     :anonymous,      default: true
      t.string      :image_attachment
      t.integer     :status,         null: false, default: 0
      t.integer     :admin_status,   null: false, default: 0
      t.integer     :upvotes_count,  default: 0
      t.boolean     :pinned,         default: false
      t.text        :admin_reply
      t.datetime    :admin_replied_at
      t.integer     :moderation_status, default: 0
      t.float       :priority_score
      t.string      :cluster_label
      t.text        :moderation_reason
      t.jsonb       :ai_analysis,    default: {}
      t.timestamps
    end
    add_index :feedbacks, :status
    add_index :feedbacks, :moderation_status
    add_index :feedbacks, :pinned
  end
end
