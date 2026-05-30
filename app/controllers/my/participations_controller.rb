class My::ParticipationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @vote_responses = VoteResponse.where(user_id: current_user.id)
                                  .includes(:vote)
                                  .order(created_at: :desc)
                                  .limit(50)

    @survey_responses = Response.where(user_id: current_user.id)
                                .includes(:survey)
                                .order(created_at: :desc)
                                .limit(50)
  end
end
