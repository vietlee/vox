class My::ParticipationsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_participant!

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

  private

  def ensure_participant!
    # Admin/supporter should go to dashboard, not here
    if current_user.workspace_member?
      redirect_to dashboard_path
    end
  end
end
