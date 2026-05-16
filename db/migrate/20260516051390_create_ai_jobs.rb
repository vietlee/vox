class CreateAiJobs < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_jobs do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :user,           foreign_key: true
      t.string      :job_type,       null: false
      t.integer     :status,         null: false, default: 0
      t.string      :resource_type
      t.integer     :resource_id
      t.jsonb       :input_data,     default: {}
      t.jsonb       :output_data,    default: {}
      t.integer     :credits_cost,   default: 0
      t.string      :model_used
      t.text        :error_message
      t.datetime    :started_at
      t.datetime    :completed_at
      t.timestamps
    end
    add_index :ai_jobs, :status
    add_index :ai_jobs, :job_type
    add_index :ai_jobs, [:resource_type, :resource_id]
  end
end
