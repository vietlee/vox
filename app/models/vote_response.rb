class VoteResponse < ApplicationRecord
  belongs_to :vote
  belongs_to :workspace

  validates :vote, :workspace, presence: true
  validate :prevent_duplicate_response, on: :create
  validate :validate_selected_options, on: :create

  after_create :update_vote_counts

  private

  def validate_selected_options
    return if vote.nil? || selected_option_ids.blank?

    # All submitted option IDs must belong to this vote
    valid_ids = vote.vote_options.pluck(:id)
    if (selected_option_ids - valid_ids).any?
      errors.add(:base, :invalid_options) and return
    end

    # single_choice: only 1 option allowed
    if vote.single_choice? && selected_option_ids.size > 1
      errors.add(:base, :invalid_options)
    end

    # multiple_choice: cannot select more options than exist
    if vote.multiple_choice? && selected_option_ids.size > valid_ids.size
      errors.add(:base, :invalid_options)
    end
  end

  def prevent_duplicate_response
    return if vote.nil? || vote.allow_multiple_votes?

    # 1. Strongest: user_id (logged-in, covers all devices/browsers)
    if user_id.present?
      if vote.vote_responses.where(user_id: user_id).exists?
        errors.add(:base, :already_voted) and return
      end
    end

    # 2. Browser fingerprint (anonymous — works across cookie deletion/incognito/different browsers on same device)
    if fingerprint.present?
      if vote.vote_responses.where(fingerprint: fingerprint).exists?
        errors.add(:base, :already_voted) and return
      end
    end

    # 3. Cookie token fallback (weakest — still catches simple repeat submissions)
    return if respondent_token.blank?
    if vote.vote_responses.exists?(respondent_token: respondent_token)
      errors.add(:base, :already_voted)
    end
  end

  def update_vote_counts
    vote.increment!(:participant_count)
    if selected_option_ids.present?
      # Scope by vote_id to prevent cross-vote option injection
      VoteOption.where(id: selected_option_ids, vote_id: vote_id).each do |opt|
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
