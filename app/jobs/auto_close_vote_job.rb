class AutoCloseVoteJob < ApplicationJob
  queue_as :default

  def perform(vote_id, opened_at_timestamp)
    vote = Vote.find_by(id: vote_id)
    return unless vote&.active?

    # Guard: only close if opened_at matches (prevents stale jobs from a re-open)
    return unless vote.opened_at.to_i == opened_at_timestamp.to_i

    vote.close!
    Rails.logger.info "[AutoCloseVoteJob] Vote ##{vote_id} auto-closed after #{vote.countdown_seconds}s"
  end
end
