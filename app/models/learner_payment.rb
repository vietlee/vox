class LearnerPayment < ApplicationRecord
  belongs_to :learner

  enum :status,  { pending: 0, completed: 1, failed: 2, refunded: 3 }
  enum :gateway, { payos: "payos" }

  validates :amount_cents, :credits_amount, numericality: { greater_than: 0 }

  def amount_formatted
    "#{amount_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫"
  end
end
