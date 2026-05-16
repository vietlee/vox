class CreateAiAnalysisResults < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_analysis_results do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :ai_job,         null: false, foreign_key: true
      t.string      :result_type,    null: false
      t.string      :resource_type
      t.integer     :resource_id
      t.jsonb       :output,         null: false, default: {}
      t.integer     :credits_cost,   default: 0
      t.integer     :response_count
      t.timestamps
    end
    add_index :ai_analysis_results, [:resource_type, :resource_id]
    add_index :ai_analysis_results, :result_type
  end
end
