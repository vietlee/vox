class Api::Learner::V1::DailyChallengesController < Api::Learner::V1::BaseController
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
    LearnerGamification.record!(current_learner, :daily_challenge)

    render json: { ok: true, correct: correct, total: @challenge.total, score_pct: @challenge.score_pct }
  end

  private

  def load_challenge
    @challenge = LearnerDailyChallenge.generate!(current_learner)
  end
end
