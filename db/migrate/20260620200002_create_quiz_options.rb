class CreateQuizOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :quiz_options do |t|
      t.references :quiz_question, null: false, foreign_key: true
      t.text    :option_text, null: false
      t.boolean :is_correct, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
