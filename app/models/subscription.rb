class Subscription < ApplicationRecord
  belongs_to :workspace
  belongs_to :user, optional: true
  has_many :payments, dependent: :destroy

  enum :plan,   { free: 0, pro: 1, enterprise: 2 }
  enum :status, { active: 0, expired: 1, cancelled: 2, trialing: 3 }

  validates :plan, presence: true
  validates :credit_balance, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(status: :active) }

  FREE_MONTHLY_CREDITS = 100 # fallback default; live value from PlanConfig.monthly_free_credits

  def self.monthly_free_credits
    PlanConfig.monthly_free_credits
  end

  def deduct_credits!(amount)
    raise "Insufficient AI credits" if credit_balance < amount
    update!(credit_balance: credit_balance - amount, credit_used: credit_used + amount)
  end

  def credit_percentage
    return 0 if max_ai_credits.nil? || max_ai_credits == 0
    ((credit_balance.to_f / max_ai_credits) * 100).round
  end

  def has_feature?(_feature)
    true
  end

  def within_survey_limit?       = true
  def within_vote_limit?         = true
  def within_dynamic_form_limit? = true
  def within_feedback_limit?     = true
  def within_supporter_limit?    = true

  def expires_soon? = false

  def surveys_used      = workspace.surveys_created_count
  def votes_used        = workspace.votes_created_count
  def dynamic_forms_used = workspace.dynamic_forms_created_count
  def feedbacks_used    = workspace.feedbacks_created_count
  def supporters_used   = workspace.workspace_memberships.active.where(role: :supporter).count

  def surveys_remaining      = nil
  def votes_remaining        = nil
  def dynamic_forms_remaining = nil
  def feedbacks_remaining    = nil
  def supporters_remaining   = nil

  def surveys_pct       = 0
  def votes_pct         = 0
  def dynamic_forms_pct = 0
  def feedbacks_pct     = 0
  def supporters_pct    = 0

  def next_credit_reset_at
    today = Date.current
    Date.new(today.year, today.month, 1).next_month.beginning_of_day
  end

  def next_credit_reset_formatted(locale = I18n.locale)
    date = next_credit_reset_at
    I18n.l(date.to_date, format: :long, locale: locale)
  rescue
    date.strftime("%d/%m/%Y")
  end
end
