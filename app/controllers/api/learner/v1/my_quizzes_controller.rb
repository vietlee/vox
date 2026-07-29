class Api::Learner::V1::MyQuizzesController < Api::Learner::V1::BaseController
  GENERATE_COST = LearnerQuizGenerator::COST

  def index
    quizzes = QuizSet.where(learner_id: current_learner.id).order(created_at: :desc)
    assignments = current_learner.quiz_assignments
                    .where(quiz_set_id: quizzes.map(&:id))
                    .index_by(&:quiz_set_id)

    render json: quizzes.map { |q|
      a = assignments[q.id]
      {
        id: q.id,
        title: q.title,
        question_count: q.quiz_questions.count,
        created_at: q.created_at,
        assignment_token: a&.token,
        assignment_status: a&.status
      }
    }
  end

  def generate
    unless current_learner.credits >= GENERATE_COST
      return render json: { error: "Không đủ credits. Cần #{GENERATE_COST} credits để tạo bài kiểm tra." },
                    status: :payment_required
    end

    title = params[:title].to_s.strip
    return render json: { error: "Vui lòng nhập tiêu đề." } if title.blank?

    attachments = []
    Array(params[:images]).each do |img|
      data = img[:data].presence || img["data"]
      mime = img[:mime].presence  || img["mime"]
      next unless data.present? && mime.present?
      attachments << { data: data, mime: mime, filename: "image.#{mime.to_s.split('/').last}" }
    end
    Array(params[:files]).each do |f|
      data = f[:data].presence || f["data"]
      mime = f[:mime].presence  || f["mime"]
      name = f[:filename].presence || f["filename"] || "document"
      next unless data.present? && mime.present?
      attachments << { data: data, mime: mime, filename: name }
    end

    result = LearnerQuizGenerator.new(
      current_learner,
      title:         title,
      prompt:        params[:prompt],
      count:         params[:count],
      include_essay: [true, "true", "1", 1].include?(params[:include_essay]),
      time_limit:    params[:time_limit],
      passing_score: params[:passing_score],
      attachments:   attachments
    ).generate!

    render json: {
      quiz_set_id:       result[:assignment].quiz_set_id,
      assignment_token:  result[:assignment].token,
      credits_remaining: current_learner.reload.credits
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Editable content of a self-generated quiz (for the review/edit screen).
  def content
    quiz = QuizSet.find_by!(id: params[:id], learner_id: current_learner.id)
    render json: {
      id:    quiz.id,
      title: quiz.title,
      questions: quiz.quiz_questions.order(:position).map { |q|
        {
          id:            q.id,
          question_text: q.question_text,
          question_type: q.question_type,
          explanation:   q.explanation,
          essay_rubric:  q.essay_rubric,
          options: q.quiz_options.order(:position).map { |o|
            { id: o.id, option_text: o.option_text, is_correct: o.is_correct }
          }
        }
      }
    }
  end

  # Save edits made in the review screen before the learner uses the quiz.
  def update
    quiz = QuizSet.find_by!(id: params[:id], learner_id: current_learner.id)
    ActiveRecord::Base.transaction do
      quiz.update!(title: params[:title].to_s.strip) if params[:title].present?
      Array(params[:questions]).each do |q|
        question = quiz.quiz_questions.find_by(id: q[:id] || q["id"])
        next unless question
        question.update!(
          question_text: (q[:question_text] || q["question_text"]).to_s,
          explanation:   (q[:explanation]   || q["explanation"]).to_s.presence
        )
        Array(q[:options] || q["options"]).each do |o|
          opt = question.quiz_options.find_by(id: o[:id] || o["id"])
          next unless opt
          truthy = [true, "true", "1", 1].include?(o[:is_correct].nil? ? o["is_correct"] : o[:is_correct])
          opt.update!(option_text: (o[:option_text] || o["option_text"]).to_s, is_correct: truthy)
        end
      end
    end
    render json: { ok: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    quiz = QuizSet.find_by!(id: params[:id], learner_id: current_learner.id)
    quiz.destroy!
    render json: { ok: true }
  end
end
