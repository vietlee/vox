class Learner::MyQuizzesController < Learner::BaseController
  GENERATE_COST = LearnerQuizGenerator::COST

  def index
    @quizzes = QuizSet.where(learner_id: current_learner.id).order(created_at: :desc)
    # Preload the learner's assignment token per quiz for "làm lại" links
    @assignments = current_learner.quiz_assignments.where(quiz_set_id: @quizzes.map(&:id)).index_by(&:quiz_set_id)
  end

  def new
    @cost = GENERATE_COST
  end

  def destroy
    quiz = QuizSet.find_by!(id: params[:id], learner_id: current_learner.id)
    quiz.destroy!
    render json: { ok: true }
  end

  def generate
    unless current_learner.credits >= GENERATE_COST
      return render json: { error: "Không đủ credits. Cần #{GENERATE_COST} credits để tạo bài kiểm tra." }, status: :payment_required
    end

    title = params[:title].to_s.strip
    return render json: { error: "Vui lòng nhập tiêu đề." } if title.blank?

    result = LearnerQuizGenerator.new(
      current_learner,
      title:         title,
      prompt:        params[:prompt],
      count:         params[:count],
      include_essay: [true, "true", "1", 1].include?(params[:include_essay]),
      time_limit:    params[:time_limit],
      files:         Array(params[:files])
    ).generate!

    render json: {
      redirect_url:      take_learner_quiz_assignment_path(result[:assignment].token),
      credits_remaining: current_learner.reload.credits
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
