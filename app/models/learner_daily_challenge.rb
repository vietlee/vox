class LearnerDailyChallenge < ApplicationRecord
  belongs_to :learner

  QUESTION_COUNT = 5

  def self.for_today(learner)
    find_or_initialize_by(learner: learner, challenge_date: Date.current)
  end

  def self.generate!(learner)
    challenge = for_today(learner)
    return challenge if challenge.persisted? && challenge.questions.present?

    questions = DailyChallengeService.new(learner).generate(QUESTION_COUNT)
    challenge.assign_attributes(questions: questions, total: questions.size)
    challenge.save!
    challenge
  end

  def submit!(answers_hash)
    return if completed?

    correct = 0
    questions.each do |q|
      answer = answers_hash[q["id"].to_s].to_i
      correct += 1 if answer == q["correct_index"]
    end

    update!(
      submitted_answers: answers_hash,
      score: correct,
      completed: true,
      completed_at: Time.current
    )
    correct
  end

  def score_pct
    return 0 if total.to_i.zero?
    (score.to_f / total * 100).round
  end
end
