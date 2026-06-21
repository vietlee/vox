class CreateFlashcards < ActiveRecord::Migration[7.2]
  def change
    create_table :flashcard_decks do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string  :title,       null: false
      t.string  :subject
      t.boolean :ai_generated, default: false
      t.integer :card_count,   default: 0
      t.timestamps
    end

    create_table :flashcards do |t|
      t.references :flashcard_deck, null: false, foreign_key: true
      t.text    :front,  null: false
      t.text    :back,   null: false
      t.integer :position, default: 0
      t.timestamps
    end

    create_table :flashcard_reviews do |t|
      t.references :flashcard, null: false, foreign_key: true
      t.references :user,      null: false, foreign_key: true
      t.integer  :rating,         default: 0  # 0=again,1=hard,2=good,3=easy
      t.integer  :interval_days,  default: 1
      t.float    :ease_factor,    default: 2.5
      t.datetime :next_review_at
      t.timestamps
    end
    add_index :flashcard_reviews, [:flashcard_id, :user_id], unique: true
    add_index :flashcard_reviews, [:user_id, :next_review_at]
  end
end
