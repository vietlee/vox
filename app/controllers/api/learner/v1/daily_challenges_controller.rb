class Api::Learner::V1::DailyChallengesController < Api::Learner::V1::BaseController
  CREDITS_PER_CORRECT = 2

  before_action :load_challenge

  def show
    questions = @challenge.questions.map do |q|
      { id: q["id"], text: q["text"], options: q["options"] }
    end

    render json: {
      id: @challenge.id,
      challenge_date: @challenge.challenge_date,
      completed: @challenge.completed,
      score_pct: @challenge.completed ? @challenge.score_pct : nil,
      questions: @challenge.completed? ? [] : questions
    }
  end

  def submit
    if @challenge.completed?
      return render json: { error: "Thử thách hôm nay đã hoàn thành." }, status: :unprocessable_entity
    end

    answers = params[:answers]&.to_unsafe_h || {}
    correct = @challenge.submit!(answers)
    gam     = LearnerGamification.record!(current_learner, :daily_challenge)

    # Reward credits for correct answers (2 each). Safe to grant unconditionally —
    # the challenge is once per day (guarded by the completed? check above).
    credits_awarded = correct.to_i * CREDITS_PER_CORRECT
    current_learner.add_credits!(credits_awarded) if credits_awarded > 0

    render json: {
      ok:                true,
      correct:           correct,
      total:             @challenge.total,
      score_pct:         @challenge.score_pct,
      xp_earned:         gam[:xp_gained].to_i,
      credits_awarded:   credits_awarded,
      credits_remaining: current_learner.reload.credits
    }
  end

  private

  def load_challenge
    @challenge = LearnerDailyChallenge.generate!(current_learner)
  end
end
