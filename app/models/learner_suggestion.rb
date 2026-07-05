class LearnerSuggestion < ApplicationRecord
  belongs_to :learner

  scope :active, -> { where(dismissed_at: nil).where("expires_at > ?", Time.current) }

  def dismissed?  = dismissed_at.present?
  def expired?    = expires_at <= Time.current
  def active?     = !dismissed? && !expired?

  ICONS = {
    "deadline"    => "🚨",
    "low_score"   => "📉",
    "abandoned"   => "😴",
    "ai_trending" => "✨"
  }.freeze

  def icon = ICONS[kind] || "💡"
end
