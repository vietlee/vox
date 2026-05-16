class VoteChannel < ApplicationCable::Channel
  def subscribed
    vote = Vote.find_by(id: params[:vote_id])
    return reject unless vote

    stream_from "vote_#{vote.id}"
  end

  def unsubscribed
  end
end
