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
    "free"       => { ai_survey_builder: false, ai_analysis: false, ai_executive_report: false, ai_chat: false, ai_moderation: false, custom_branding: false, export: false, sso: false, tts: false },
    "pro"        => { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: false, ai_moderation: true, custom_branding: true, export: true, sso: false, tts: true },
    "enterprise" => { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: true, ai_moderation: true, custom_branding: true, export: true, sso: true, tts: true }
  }.freeze

  def deduct_credits!(amount)
    # Enterprise: deduct for display but never block (unlimited)
    if enterprise?
      new_balance = [credit_balance - amount, 0].max
      update_columns(credit_balance: new_balance, credit_used: credit_used + amount)
      return true
    end
    raise "Insufficient AI credits" if credit_balance < amount
    update!(credit_balance: credit_balance - amount, credit_used: credit_used + amount)
  end

  def credit_percentage
    return 0 if max_ai_credits.nil? || max_ai_credits == 0
    ((credit_balance.to_f / max_ai_credits) * 100).round
  end

  def has_feature?(feature)
    key = feature.to_sym
    # PlanConfig is the source of truth — super admin controls this live from DB.
    # The subscription.features column is a stale snapshot set at activation time
    # and may be out of date if the plan config was changed after activation.
    plan_features = PlanConfig.features_for(plan)
    return plan_features[key] if plan_features.key?(key)
    # Fall back to hardcoded defaults if PlanConfig record is missing
    FEATURE_FLAGS.dig(plan, key) || false
  end

  def within_survey_limit?
    max_surveys.nil? || workspace.surveys_created_count < max_surveys
  end

  def within_vote_limit?
    max_votes.nil? || workspace.votes_created_count < max_votes
  end

  def within_feedback_limit?
    max_feedbacks.nil? || workspace.feedbacks_created_count < max_feedbacks
  end

  def within_supporter_limit?
    return true if max_supporters.nil?
    current_count = workspace.workspace_memberships.active.where(role: :supporter).count
    current_count < max_supporters
  end

  def surveys_used      = workspace.surveys_created_count
  def surveys_remaining = max_surveys.nil? ? nil : [max_surveys - surveys_used, 0].max
  def surveys_pct       = max_surveys.nil? ? 0 : [(surveys_used * 100.0 / max_surveys).round, 100].min

  def votes_used = workspace.votes_created_count
  def votes_remaining = max_votes.nil? ? nil : [max_votes - votes_used, 0].max
  def votes_pct = max_votes.nil? ? 0 : [(votes_used * 100.0 / max_votes).round, 100].min

  def feedbacks_used = workspace.feedbacks_created_count
  def feedbacks_remaining = max_feedbacks.nil? ? nil : [max_feedbacks - feedbacks_used, 0].max
  def feedbacks_pct = max_feedbacks.nil? ? 0 : [(feedbacks_used * 100.0 / max_feedbacks).round, 100].min

  def supporters_used = workspace.workspace_memberships.active.where(role: :supporter).count
  def supporters_remaining = max_supporters.nil? ? nil : [max_supporters - supporters_used, 0].max
  def supporters_pct = max_supporters.nil? ? 0 : max_supporters == 0 ? 0 : [(supporters_used * 100.0 / max_supporters).round, 100].min

  def expires_soon?
    ends_at.present? && ends_at <= 7.days.from_now
  end

  # For free plan: date when counts will next be reset (1st of next month)
  def next_reset_at
    return nil unless free?
    today = Date.current
    Date.new(today.year, today.month, 1).next_month.beginning_of_day
  end

  def next_reset_date_formatted(locale = I18n.locale)
    return nil unless (date = next_reset_at)
    I18n.l(date.to_date, format: :long, locale: locale)
  rescue
    date.strftime("%d/%m/%Y")
  end
end
