class CreateVoteResponses < ActiveRecord::Migration[7.2]
  def change
    create_table :vote_responses do |t|
      t.references  :vote,           null: false, foreign_key: true
      t.references  :workspace,      null: false, foreign_key: true
      t.string      :respondent_token
      t.string      :respondent_email
      t.jsonb       :selected_option_ids, default: []
      t.text        :text_value
      t.jsonb       :ranking_order,   default: []
      t.integer     :upvote_target_id
      t.timestamps
    end
  end
end
