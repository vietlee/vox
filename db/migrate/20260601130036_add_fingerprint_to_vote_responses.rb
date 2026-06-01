class AddFingerprintToVoteResponses < ActiveRecord::Migration[7.2]
  def change
    add_column :vote_responses, :fingerprint, :string
    add_index  :vote_responses, [:vote_id, :fingerprint], name: "index_vote_responses_on_vote_and_fingerprint"
  end
end
