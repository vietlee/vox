class AddLearnerIdToFlashcardReviews < ActiveRecord::Migration[7.2]
  def change
    add_column :flashcard_reviews, :learner_id, :bigint
    change_column_null :flashcard_reviews, :user_id, true
    add_index :flashcard_reviews, [:learner_id, :next_review_at],
              name: "index_fc_reviews_on_learner_and_next_review"
    add_index :flashcard_reviews, [:flashcard_id, :learner_id], unique: true,
              name: "index_fc_reviews_on_flashcard_and_learner",
              where: "learner_id IS NOT NULL"
  end
end
