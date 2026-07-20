class Api::Learner::V1::QuizAssignmentsController < Api::Learner::V1::BaseController
  GRADE_COST = 2

  before_action :set_assignment
  before_action :ensure_published, except: [:show, :result]

  def show
    render json: {
      assignment: {
        token: @assignment.token,
        status: @assignment.status,
        title: @assignment.quiz_set.title,
        progress_pct: @assignment.progress_pct
      },
      quiz_set: {
        title: @assignment.quiz_set.title,
        published: @assignment.quiz_set.published?
      }
    }
  end

  def take
    @assignment.in_progress! if @assignment.pending?
    quiz_set  = @assignment.quiz_set
    questions = quiz_set.quiz_questions.includes(:quiz_options).order(:position)
    attempt   = find_or_build_attempt

    render json: {
      assignment: {
        token: @assignment.token,
        status: @assignment.status,
        title: quiz_set.title,
        progress_pct: @assignment.progress_pct
      },
      questions: questions.map { |q|
        {
          id: q.id,
          text: q.question_text,
          kind: q.question_type,
          options: q.quiz_options.order(:position).map { |o| { id: o.id, text: o.option_text } }
        }
      }
    }
  end

  def save_answer
    attempt = current_learner_attempt
    return render json: { ok: false } unless attempt

    answer = attempt.quiz_attempt_answers.find_or_initialize_by(
      quiz_question_id: params[:question_id]
    )
    answer.update(
      quiz_option_id: params[:option_id],
      text_answer:    params[:text_answer]
    )
    render json: { ok: true }
  end

  def submit
    attempt = current_learner_attempt
    return render json: { error: "Không tìm thấy bài làm." }, status: :not_found unless attempt

    was_completed = @assignment.completed?

    if @assignment.quiz_set.learner_id.present?
      if current_learner.credits >= GRADE_COST
        LearnerQuizGrader.new(attempt).grade!
        current_learner.deduct_credits!(GRADE_COST)
      else
        calculate_score(attempt)
      end
    else
      calculate_score(attempt)
    end

    attempt.update!(submitted_at: Time.current)
    @assignment.completed!
    @assignment.update!(completed_at: Time.current)
    LearnerGamification.record!(current_learner, :quiz_complete) unless was_completed

    attempt.reload
    render json: {
      score_pct: attempt.score_pct,
      passed: attempt.passed?,
      redirect_to_result: true
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def result
    quiz_set  = @assignment.quiz_set
    attempt   = quiz_set.quiz_attempts
                  .where(participant_email: current_learner.email)
                  .order(created_at: :desc).first

    questions    = quiz_set.quiz_questions.includes(:quiz_options).order(:position)
    answers_by_q = attempt ? attempt.quiz_attempt_answers.index_by(&:quiz_question_id) : {}

    render json: {
      quiz_set: { title: quiz_set.title, published: quiz_set.published? },
      assignment: { token: @assignment.token, status: @assignment.status },
      score_pct: attempt&.score_pct,
      passed: attempt&.passed?,
      questions: questions.map { |q|
        ans = answers_by_q[q.id]
        {
          id: q.id,
          text: q.question_text,
          kind: q.question_type,
          explanation: q.explanation,
          options: q.quiz_options.order(:position).map { |o|
            { id: o.id, text: o.option_text, is_correct: o.is_correct? }
          },
          selected_option_id: ans&.quiz_option_id,
          text_answer: ans&.text_answer,
          ai_feedback: ans&.try(:ai_feedback)
        }
      }
    }
  end

  def destroy
    @assignment.destroy!
    render json: { ok: true }
  end

  private

  def set_assignment
    @assignment = current_learner.quiz_assignments.find_by!(token: params[:token])
  end

  def ensure_published
    unless @assignment.quiz_set.published?
      render json: { error: "Bài kiểm tra này chưa được mở. Vui lòng liên hệ admin." },
             status: :forbidden
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
    attempt.quiz_attempt_answers.includes(quiz_question: :quiz_options).each do |ans|
      q = ans.quiz_question
      total += 1
      if ans.quiz_option_id.present?
        opt = q.quiz_options.find { |o| o.id == ans.quiz_option_id }
        earned += 1 if opt&.is_correct?
      end
    end
    attempt.update!(total_points: total, earned_points: earned)
  end
end
