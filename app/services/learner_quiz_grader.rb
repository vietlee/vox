# Grades a learner's attempt on a self-created quiz: auto-scores multiple choice,
# uses AI to grade essays, and produces an overall AI evaluation (nhận xét).
class LearnerQuizGrader
  def initialize(attempt)
    @attempt = attempt
    @quiz    = attempt.quiz_set
  end

  def grade!
    answers   = @attempt.quiz_attempt_answers.includes(quiz_question: :quiz_options)
    total     = 0
    earned    = 0.0
    essays    = [] # [{answer:, question:}]

    answers.each do |ans|
      q = ans.quiz_question
      next unless q
      pts = q.points.to_f
      total += pts

      if q.essay? || q.short_answer?
        essays << { answer: ans, question: q }
      else
        opt = q.quiz_options.find { |o| o.id == ans.quiz_option_id }
        correct = opt&.is_correct?
        ans.update_columns(is_correct: !!correct)
        earned += pts if correct
      end
    end

    ai = grade_with_ai(essays)

    # Apply essay grades
    essays.each_with_index do |e, i|
      g = ai.dig("essays", i) || {}
      max   = e[:question].points.to_f
      grade = [[g["grade"].to_f, 0].max, max].min
      earned += grade
      e[:answer].update_columns(
        ai_grade:    grade.round,
        ai_feedback: g["feedback"].to_s,
        is_correct:  grade >= max * 0.5,
        ai_graded_at: Time.current
      )
    end

    total_i  = total.round
    earned_i = earned.round
    pct      = total_i.positive? ? (earned_i * 100.0 / total_i).round : 0

    @attempt.update!(
      total_points:  total_i,
      earned_points: earned_i,
      score:         pct,
      ai_evaluation: ai["overall"].to_s.presence,
      ai_evaluated_at: Time.current
    )
  end

  private

  # Single AI call: grade every essay + produce an overall evaluation in Vietnamese.
  def grade_with_ai(essays)
    total  = @attempt.quiz_attempt_answers.count
    essay_block = essays.each_with_index.map do |e, i|
      "[#{i}] Câu hỏi: #{e[:question].question_text}\nRubric: #{e[:question].essay_rubric.presence || '(không có)'}\nĐiểm tối đa: #{e[:question].points}\nBài làm: #{(e[:answer].essay_text.presence || e[:answer].text_answer).to_s.truncate(1500)}"
    end.join("\n\n")

    mc_correct = @attempt.quiz_attempt_answers.select { |a| a.quiz_question && !a.quiz_question.essay? && !a.quiz_question.short_answer? && a.is_correct? }.count
    mc_total   = @attempt.quiz_attempt_answers.select { |a| a.quiz_question && !a.quiz_question.essay? && !a.quiz_question.short_answer? }.count

    system = <<~P
      Bạn là giáo viên chấm bài. Trả về DUY NHẤT JSON hợp lệ:
      {"essays":[{"grade":<số điểm 0..max>,"feedback":"nhận xét ngắn bằng tiếng Việt"}],
       "overall":"nhận xét tổng quan 2-4 câu bằng tiếng Việt: điểm mạnh, điểm cần cải thiện, lời khuyên"}
      Mảng "essays" theo đúng thứ tự các câu tự luận được cung cấp (nếu không có câu tự luận, để [] ).
    P

    user = <<~P
      Bài kiểm tra: #{@quiz.title}
      Trắc nghiệm: đúng #{mc_correct}/#{mc_total} câu.
      #{essays.any? ? "Các câu tự luận cần chấm:\n#{essay_block}" : "Không có câu tự luận."}
    P

    svc = ClaudeService.for_feature("quiz_generate", timeout: 60)
    raw = svc.call(system_prompt: system, messages: [{ role: "user", content: user }], max_tokens: 2000)
    m = raw.match(/\{[\s\S]*\}/)
    m ? JSON.parse(m[0]) : {}
  rescue => e
    Rails.logger.warn("[LearnerQuizGrader] #{e.message}")
    {}
  end
end
