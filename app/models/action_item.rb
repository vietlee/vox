class ActionItem < ApplicationRecord
  belongs_to :workspace
  belongs_to :feedback_board
  belongs_to :assignee, class_name: "User", foreign_key: :assignee_id, optional: true
  belongs_to :ai_analysis_result, optional: true

  enum :priority, { low: 0, medium: 1, high: 2 }
  enum :status,   { pending: 0, in_progress: 1, done: 2 }

  validates :title, presence: true

  # in_progress (1) first so active work is always visible, then pending (0), done (2) last
  scope :ordered, -> { order(Arel.sql("CASE status WHEN 1 THEN 0 WHEN 0 THEN 1 WHEN 2 THEN 2 END"), priority: :desc, created_at: :asc) }
end
