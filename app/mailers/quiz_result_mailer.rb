class QuizResultMailer < ApplicationMailer
  def result_email(attempt, quiz_set)
    @attempt  = attempt
    @quiz_set = quiz_set
    @workspace = quiz_set.workspace
    @questions = quiz_set.quiz_questions.includes(:quiz_options)
    @answers_by_q = attempt.quiz_attempt_answers.includes(:quiz_option).group_by(&:quiz_question_id)

    mail(
      to:      attempt.participant_email,
      subject: "Kết quả bài thi: #{quiz_set.title}"
    )
  end

  def ai_evaluation_email(attempt, quiz_set)
    @attempt  = attempt
    @quiz_set = quiz_set
    @workspace = quiz_set.workspace

    mail(
      to:      attempt.participant_email,
      subject: "Nhận xét bài thi: #{quiz_set.title}"
    )
  end
end
