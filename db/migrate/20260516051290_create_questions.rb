class CreateQuestions < ActiveRecord::Migration[7.2]
  def change
    create_table :questions do |t|
      t.references  :survey,         null: false, foreign_key: true
      t.string      :title,          null: false
      t.text        :description
      t.string      :image
      t.integer     :question_type,  null: false, default: 0
      t.integer     :position,       null: false, default: 0
      t.integer     :section,        default: 0
      t.boolean     :required,       default: false
      t.jsonb       :settings,       default: {}
      t.jsonb       :conditional_logic, default: {}
      t.integer     :score_weight,   default: 0
      t.timestamps
    end
    add_index :questions, [:survey_id, :position]
  end
end
