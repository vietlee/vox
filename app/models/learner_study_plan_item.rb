class LearnerStudyPlanItem < ApplicationRecord
  belongs_to :learner_study_plan

  ICONS = { "flashcard" => "🃏", "quiz" => "📝", "tutor" => "💬", "read" => "📖" }.freeze
  def icon = ICONS[kind] || "•"
end
