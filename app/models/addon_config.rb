class AddonConfig < ApplicationRecord
  enum :addon_type, { resource_pack: "resource_pack", ai_credits: "ai_credits" }

  validates :name, presence: true
  validates :price_cents, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true).order(:sort_order, :price_cents) }

  def price_formatted
    "#{price_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫"
  end

  def bonus_summary
    parts = []
    parts << "#{surveys_bonus} survey"    if surveys_bonus.to_i > 0
    parts << "#{votes_bonus} vote"        if votes_bonus.to_i > 0
    parts << "#{feedbacks_bonus} feedback" if feedbacks_bonus.to_i > 0
    parts << "#{ai_credits_bonus} AI credit" if ai_credits_bonus.to_i > 0
    parts.join(", ")
  end
end
