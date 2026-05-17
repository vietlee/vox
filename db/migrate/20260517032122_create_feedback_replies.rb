class CreateFeedbackReplies < ActiveRecord::Migration[7.2]
  def change
    create_table :feedback_replies do |t|
      t.references :feedback, null: false, foreign_key: true
      t.string :author_name
      t.boolean :anonymous, default: true
      t.text :content

      t.timestamps
    end
  end
end
