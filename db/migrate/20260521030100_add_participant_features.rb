class AddParticipantFeatures < ActiveRecord::Migration[7.2]
  def change
    # Vote: require SSO login options
    add_column :votes, :login_required,  :boolean, default: false, null: false
    add_column :votes, :login_providers, :string,  default: "both"

    # Track which user submitted a vote/survey response
    add_column :vote_responses, :user_id, :bigint
    add_index  :vote_responses, :user_id
    add_foreign_key :vote_responses, :users, column: :user_id, on_delete: :nullify

    add_column :responses, :user_id, :bigint
    add_index  :responses, :user_id
    add_foreign_key :responses, :users, column: :user_id, on_delete: :nullify
  end
end
