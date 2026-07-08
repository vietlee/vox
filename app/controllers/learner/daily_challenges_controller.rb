class Learner::DailyChallengesController < Learner::BaseController
  before_action :load_challenge, only: [:show, :submit]

  def show; end

  def submit
    return redirect_to learner_daily_challenge_path if @challenge.completed?

    answers = params[:answers]&.to_unsafe_h || {}
    correct = @challenge.submit!(answers)
    LearnerGamification.record!(current_learner, :daily_challenge)

    render json: { ok: true, correct: correct, total: @challenge.total, score_pct: @challenge.score_pct }
  end

  private

  def load_challenge
    @challenge = LearnerDailyChallenge.generate!(current_learner)
  end
end
