class PlanConfig < ApplicationRecord
  validates :plan_key, presence: true, uniqueness: true
  validates :price_vnd, numericality: { greater_than_or_equal_to: 0 }

  DEFAULTS = {
    "free" => {
      display_name: "Free",
      price_vnd: 0,
      limits: { max_surveys: 3, max_votes: 3, max_feedbacks: 10, max_supporters: 0, max_ai_credits: 0 },
      features: { ai_survey_builder: false, ai_analysis: false, ai_executive_report: false, ai_chat: false, ai_moderation: false, custom_branding: false, export: false, sso: false }
    },
    "pro" => {
      display_name: "Pro",
      price_vnd: 1_000_000,
      limits: { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: 10, max_ai_credits: 500 },
      features: { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: false, ai_moderation: true, custom_branding: true, export: true, sso: false }
    },
    "enterprise" => {
      display_name: "Enterprise",
      price_vnd: 0,
      limits: { max_surveys: nil, max_votes: nil, max_feedbacks: nil, max_supporters: nil, max_ai_credits: nil },
      features: { ai_survey_builder: true, ai_analysis: true, ai_executive_report: true, ai_chat: true, ai_moderation: true, custom_branding: true, export: true, sso: true }
    }
  }.freeze

  def self.find_for(plan_key)
    Rails.cache.fetch("plan_config/#{plan_key}", expires_in: 5.minutes) do
      find_by(plan_key: plan_key.to_s)
    end
  end

  def self.price_for(plan_key)
    config = find_for(plan_key)
    return config.price_vnd if config
    DEFAULTS.dig(plan_key.to_s, :price_vnd) || 0
  end

  def self.limits_for(plan_key)
    config = find_for(plan_key)
    return config.limits.symbolize_keys if config&.limits&.any?
    DEFAULTS.dig(plan_key.to_s, :limits) || {}
  end

  def self.features_for(plan_key)
    config = find_for(plan_key)
    return config.features.transform_keys(&:to_sym) if config&.features&.any?
    DEFAULTS.dig(plan_key.to_s, :features) || {}
  end

  def self.seed_defaults!
    DEFAULTS.each do |key, attrs|
      find_or_create_by!(plan_key: key) do |pc|
        pc.display_name  = attrs[:display_name]
        pc.price_vnd     = attrs[:price_vnd]
        pc.limits        = attrs[:limits]
        pc.features      = attrs[:features]
      end
    end
  end

  def self.invalidate_cache!(plan_key)
    Rails.cache.delete("plan_config/#{plan_key}")
  end

  after_save    { self.class.invalidate_cache!(plan_key) }
  after_destroy { self.class.invalidate_cache!(plan_key) }
end
