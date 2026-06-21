class QuizController < ApplicationController
  layout "quiz"
  skip_before_action :authenticate_user!, raise: false

  before_action :set_quiz_set, except: [:public_result]

  def show
    if params[:attempt_id]
      @attempt = @quiz_set.quiz_attempts.find_by(id: params[:attempt_id])
      return redirect_to quiz_path(@quiz_set.share_token) if @attempt.nil? || !@attempt.submitted?
      if params[:thankyou] == "1"
        @already_done = params[:already_done] == "1"
        return render :thankyou
      end
      return render :result
    end
    # Landing page: check if already submitted + retake blocked
    if params[:email].present?
      submitted = @quiz_set.quiz_attempts.where(participant_email: params[:email].downcase).where.not(submitted_at: nil).first
      @already_submitted = submitted && !@quiz_set.allow_retake?
      @submitted_attempt = submitted if @already_submitted
    end
  end

  def start
    email = params[:email].to_s.strip.downcase

    # Check if already submitted
    submitted = @quiz_set.quiz_attempts.where(participant_email: email).where.not(submitted_at: nil).first

    if submitted && !@quiz_set.allow_retake?
      if @quiz_set.result_later?
        return redirect_to quiz_path(@quiz_set.share_token, attempt_id: submitted.id, thankyou: "1", already_done: "1")
      else
        return redirect_to quiz_path(@quiz_set.share_token, attempt_id: submitted.id)
      end
    end

    # Resume in-progress attempt, or create new
    existing = @quiz_set.quiz_attempts.find_by(participant_email: email, submitted_at: nil)
    @attempt = existing || @quiz_set.quiz_attempts.create!(
      participant_name:  params[:name].to_s.strip,
      participant_email: email,
      total_questions:   @quiz_set.quiz_questions.count,
      total_points:      @quiz_set.quiz_questions.sum(:points),
      started_at:        Time.current
    )
    @attempt.update_column(:started_at, Time.current) if @attempt.started_at.nil?
    redirect_to take_quiz_path(@quiz_set.share_token, attempt_id: @attempt.id)
  end

  def take
    @attempt = @quiz_set.quiz_attempts.find(params[:attempt_id])
    return redirect_to quiz_path(@quiz_set.share_token) if @attempt.submitted?
    @questions = @quiz_set.quiz_questions.includes(:quiz_options)
    # Group by question — multiple answers per question for allow_multiple
    @existing_answers = @attempt.quiz_attempt_answers.group_by(&:quiz_question_id)
    # Calculate true remaining seconds from server-side started_at
    if @quiz_set.time_limit_minutes.to_i > 0 && @attempt.started_at
      elapsed = (Time.current - @attempt.started_at).to_i
      @remaining_seconds = [(@quiz_set.time_limit_minutes * 60) - elapsed, 0].max
    end
  end

  def save_answer
    attempt = @quiz_set.quiz_attempts.find_by(id: params[:attempt_id])
    return render json: { ok: false }, status: :not_found unless attempt
    return render json: { ok: false, expired: true } if attempt.submitted?

    qid    = params[:question_id].to_i
    q      = @quiz_set.quiz_questions.find_by(id: qid)
    return render json: { ok: false } unless q

    if q.short_answer?
      ans = attempt.quiz_attempt_answers.find_or_initialize_by(quiz_question_id: qid)
      ans.update!(text_answer: params[:text_answer].to_s.strip, is_correct: false)
    elsif q.allow_multiple
      attempt.quiz_attempt_answers.where(quiz_question_id: qid).destroy_all
      Array(params[:option_ids]).map(&:to_i).select(&:positive?).each do |oid|
        attempt.quiz_attempt_answers.create!(quiz_question: q, quiz_option_id: oid, is_correct: false)
      end
    else
      oid = params[:option_id].to_i
      ans = attempt.quiz_attempt_answers.find_or_initialize_by(quiz_question_id: qid)
      ans.update!(quiz_option_id: oid.positive? ? oid : nil, is_correct: false)
    end

    render json: { ok: true }
  rescue => e
    render json: { ok: false, error: e.message }
  end

  def submit
    @attempt = @quiz_set.quiz_attempts.find(params[:attempt_id])
    return redirect_to quiz_path(@quiz_set.share_token) if @attempt.submitted?

    answers = params[:answers] || {}
    earned  = 0

    ActiveRecord::Base.transaction do
      @attempt.quiz_attempt_answers.destroy_all
      @quiz_set.quiz_questions.includes(:quiz_options).each do |q|
        if q.short_answer?
          @attempt.quiz_attempt_answers.create!(
            quiz_question: q,
            is_correct:    false,
            text_answer:   answers[q.id.to_s].to_s.strip
          )
        elsif q.allow_multiple
          selected_ids = Array(answers[q.id.to_s]).map(&:to_i).select(&:positive?)
          correct_ids  = q.quiz_options.where(is_correct: true).pluck(:id).sort
          all_correct  = selected_ids.sort == correct_ids && selected_ids.any?
          earned += q.points if all_correct
          if selected_ids.empty?
            @attempt.quiz_attempt_answers.create!(quiz_question: q, is_correct: false)
          else
            selected_ids.each do |oid|
              @attempt.quiz_attempt_answers.create!(
                quiz_question: q,
                quiz_option:   q.quiz_options.find_by(id: oid),
                is_correct:    all_correct
              )
            end
          end
        else
          option_id = answers[q.id.to_s].to_i
          option    = q.quiz_options.find_by(id: option_id)
          correct   = option&.is_correct? || false
          earned   += q.points if correct
          @attempt.quiz_attempt_answers.create!(
            quiz_question: q,
            quiz_option:   option,
            is_correct:    correct
          )
        end
      end
      @attempt.update!(
        earned_points: earned,
        score:         @quiz_set.quiz_questions.count > 0 ? (earned * 100 / @quiz_set.quiz_questions.sum(:points).to_f).round : 0,
        submitted_at:  Time.current,
        time_spent_seconds: params[:time_spent].to_i
      )
    end

    if @quiz_set.result_later?
      redirect_to quiz_path(@quiz_set.share_token, attempt_id: @attempt.id, thankyou: "1")
    else
      redirect_to quiz_path(@quiz_set.share_token, attempt_id: @attempt.id)
    end
  end

  def public_result
    @attempt  = QuizAttempt.find_by!(result_token: params[:result_token])
    @quiz_set = @attempt.quiz_set
    @questions = @quiz_set.quiz_questions.includes(:quiz_options)
    @answers_by_q = @attempt.quiz_attempt_answers.includes(:quiz_option).group_by(&:quiz_question_id)
    render layout: "quiz"
  end

  private

  def set_quiz_set
    @quiz_set = QuizSet.find_by!(share_token: params[:token])
    unless @quiz_set.published?
      render "not_published", status: :not_found
    end
  end
end
