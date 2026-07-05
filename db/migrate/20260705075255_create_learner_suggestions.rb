class CreateLearnerSuggestions < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_suggestions do |t|
      t.bigint  :learner_id,     null: false
      t.string  :kind            # deadline | low_score | abandoned | ai_trending
      t.string  :title,          null: false
      t.text    :body,           null: false
      t.string  :action_label
      t.string  :action_url
      t.string  :prefill_topic   # for flashcard AI create
      t.datetime :dismissed_at
      t.datetime :expires_at,    null: false
      t.timestamps
    end
    add_index :learner_suggestions, :learner_id
  end
end
