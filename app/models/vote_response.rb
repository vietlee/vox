class VoteResponse < ApplicationRecord
  belongs_to :vote
  belongs_to :workspace

  validates :vote, :workspace, presence: true
  validate :prevent_duplicate_response, on: :create

  after_create :update_vote_counts

  private

  def prevent_duplicate_response
    return if vote.nil? || vote.allow_multiple_votes?
    return if respondent_token.blank?
    if vote.vote_responses.exists?(respondent_token: respondent_token)
      errors.add(:base, :already_voted)
    end
  end

  def update_vote_counts
    vote.increment!(:participant_count)
    if selected_option_ids.present?
      VoteOption.where(id: selected_option_ids).each do |opt|
        opt.increment!(:votes_count)
      end
    end
    ActionCable.server.broadcast("vote_#{vote_id}", {
      type: "new_vote",
      options: vote.reload.results_by_option,
      participant_count: vote.participant_count
    })
  end
end
