class CreateResponses < ActiveRecord::Migration[7.2]
  def change
    create_table :responses do |t|
      t.references  :survey,         null: false, foreign_key: true
      t.references  :workspace,      null: false, foreign_key: true
      t.string      :respondent_email
      t.string      :respondent_token
      t.integer     :status,         default: 0
      t.datetime    :completed_at
      t.integer     :completion_time_seconds
      t.float       :quality_score
      t.boolean     :excluded,       default: false
      t.string      :source,         default: "link"
      t.jsonb       :metadata,       default: {}
      t.timestamps
    end
    add_index :responses, :respondent_email
    add_index :responses, :status
  end
end
