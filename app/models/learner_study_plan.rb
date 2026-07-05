class LearnerStudyPlan < ApplicationRecord
  belongs_to :learner
  has_many :items, -> { order(:position) }, class_name: "LearnerStudyPlanItem", dependent: :destroy

  enum :status, { active: 0, completed: 1 }

  def progress_pct
    total = items.count
    return 0 if total.zero?
    (items.where(done: true).count * 100.0 / total).round
  end
end
