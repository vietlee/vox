class Learner::QuizAssignmentsController < Learner::BaseController
  before_action :set_assignment
  before_action :ensure_published, except: [:show, :result]

  def show; end

  def take
    @assignment.in_progress! if @assignment.pending?
    @quiz_set   = @assignment.quiz_set
    @questions  = @quiz_set.quiz_questions.includes(:quiz_options).order(:position)
    @attempt    = find_or_build_attempt
    @attempt.quiz_attempt_answers.load
  end

  def start
    @assignment.in_progress!
    redirect_to take_learner_quiz_assignment_path(@assignment.token)
  end

  def save_answer
    attempt = current_learner_attempt
    return render json: { ok: false } unless attempt

    answer = attempt.quiz_attempt_answers.find_or_initialize_by(
      quiz_question_id: params[:question_id]
    )
    answer.update(
      quiz_option_id: params[:option_id],
      text_answer:        params[:text_answer]
    )
    render json: { ok: true }
  end

  def submit
    attempt = current_learner_attempt
    return redirect_to learner_root_path unless attempt

    was_completed = @assignment.completed?
    if @assignment.quiz_set.learner_id.present?
      LearnerQuizGrader.new(attempt).grade!   # AI grades essays + overall nhận xét
    else
      calculate_score(attempt)
    end
    attempt.update!(submitted_at: Time.current)
    @assignment.completed!
    @assignment.update!(completed_at: Time.current)
    LearnerGamification.record!(current_learner, :quiz_complete) unless was_completed
    redirect_to result_learner_quiz_assignment_path(@assignment.token)
  end

  def result
    @quiz_set  = @assignment.quiz_set
    @attempt   = current_learner.quiz_assignments
                   .find_by!(token: params[:token])
                   .quiz_set.quiz_attempts
                   .where(participant_email: current_learner.email)
                   .order(created_at: :desc).first

    # Per-question detail
    @questions = @quiz_set.quiz_questions.includes(:quiz_options).order(:position)
    @answers_by_q = @attempt ? @attempt.quiz_attempt_answers.index_by(&:quiz_question_id) : {}
  end

  private

  def set_assignment
    @assignment = current_learner.quiz_assignments.find_by!(token: params[:token])
  end

  def ensure_published
    unless @assignment.quiz_set.published?
      redirect_to learner_quiz_assignment_path(@assignment.token),
        alert: "Bài kiểm tra này chưa được mở. Vui lòng liên hệ admin."
    end
  end

  def find_or_build_attempt
    current_learner.email.then do |email|
      @assignment.quiz_set.quiz_attempts
        .find_or_create_by(participant_email: email) do |a|
          a.participant_name = current_learner.name
        end
    end
  end

  def current_learner_attempt
    @assignment.quiz_set.quiz_attempts
      .find_by(participant_email: current_learner.email)
  end

  def calculate_score(attempt)
    total = 0; earned = 0
    attempt.quiz_attempt_answers.each do |ans|
      q = ans.quiz_question
      total += 1
      if ans.quiz_option_id.present?
        opt = q.quiz_options.find_by(id: ans.quiz_option_id)
        earned += 1 if opt&.is_correct?
      end
    end
    attempt.update!(total_points: total, earned_points: earned)
  end
end
