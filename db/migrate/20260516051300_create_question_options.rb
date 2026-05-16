class CreateQuestionOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :question_options do |t|
      t.references  :question,       null: false, foreign_key: true
      t.string      :label,          null: false
      t.string      :image
      t.integer     :position,       null: false, default: 0
      t.integer     :score,          default: 0
      t.timestamps
    end
  end
end
