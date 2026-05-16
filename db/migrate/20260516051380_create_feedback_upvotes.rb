class CreateFeedbackUpvotes < ActiveRecord::Migration[7.2]
  def change
    create_table :feedback_upvotes do |t|
      t.references  :feedback,       null: false, foreign_key: true
      t.string      :voter_token,    null: false
      t.timestamps
    end
    add_index :feedback_upvotes, [:feedback_id, :voter_token], unique: true
  end
end
