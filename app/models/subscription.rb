class Subscription < ApplicationRecord
  belongs_to :workspace
  has_many :payments, dependent: :destroy

  enum :plan,   { free: 0, pro: 1, enterprise: 2 }
  enum :status, { active: 0, expired: 1, cancelled: 2, trialing: 3 }

  validates :plan, presence: true
  validates :credit_balance, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: :active) }

  PLAN_LIMITS = {
    "free"       => { max_surveys: 3, max_votes: 3, max_feedbacks: 10, max_supporters: 0, max_ai_credits: 0 },
    "pro"        => { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: 10, max_ai_credits: 500 },
    "enterprise" => { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: nil, max_ai_credits: nil }
  }.freeze

  PLAN_PRICES = {
    "free" => 0,
    "pro"  => 1_000_000,
    "enterprise" => nil
  }.freeze

  FEATURE_FLAGS = {
    "free"       => { ai_survey_builder: false, ai_analysis: false, ai_executive_report: false, ai_chat: false, ai_moderation: false, custom_branding: false, export: false, sso: false },
    "pro"        => { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: false, ai_moderation: true, custom_branding: true, export: true, sso: false },
    "enterprise" => { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: true, ai_moderation: true, custom_branding: true, export: true, sso: true }
  }.freeze

  def deduct_credits!(amount)
    return true if enterprise?
    raise "Insufficient AI credits" if credit_balance < amount
    update!(credit_balance: credit_balance - amount, credit_used: credit_used + amount)
  end

  def credit_percentage
    return 100 if max_ai_credits.nil? || max_ai_credits == 0
    ((credit_balance.to_f / max_ai_credits) * 100).round
  end

  def has_feature?(feature)
    FEATURE_FLAGS[plan][feature.to_sym]
  end

  def within_survey_limit?
    max_surveys.nil? || workspace.surveys.count < max_surveys
  end

  def within_vote_limit?
    max_votes.nil? || workspace.votes.count < max_votes
  end

  def expires_soon?
    ends_at.present? && ends_at <= 7.days.from_now
  end
end
