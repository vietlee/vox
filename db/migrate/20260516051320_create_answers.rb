class CreateAnswers < ActiveRecord::Migration[7.2]
  def change
    create_table :answers do |t|
      t.references  :response,       null: false, foreign_key: true
      t.references  :question,       null: false, foreign_key: true
      t.text        :text_value
      t.jsonb       :option_ids,     default: []
      t.jsonb       :matrix_values,  default: {}
      t.float       :numeric_value
      t.date        :date_value
      t.string      :file_attachment
      t.integer     :score,          default: 0
      t.timestamps
    end
  end
end
