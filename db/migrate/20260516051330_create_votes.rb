class CreateVotes < ActiveRecord::Migration[7.2]
  def change
    create_table :votes do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.references  :user,           null: false, foreign_key: true
      t.string      :title,          null: false
      t.integer     :vote_type,      null: false, default: 0
      t.integer     :status,         null: false, default: 0
      t.integer     :identity_mode,  null: false, default: 0
      t.integer     :countdown_seconds
      t.boolean     :show_results_live, default: true
      t.boolean     :allow_multiple_votes, default: false
      t.string      :slug
      t.integer     :participant_count, default: 0
      t.jsonb       :settings,       default: {}
      t.timestamps
    end
    add_index :votes, :slug, unique: true
    add_index :votes, :status
  end
end
