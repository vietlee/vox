class CreateActionItems < ActiveRecord::Migration[7.2]
  def change
    create_table :action_items do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :feedback_board, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.integer :priority
      t.integer :status
      t.integer :assignee_id
      t.integer :ai_analysis_result_id

      t.timestamps
    end
  end
end
