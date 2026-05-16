class Payment < ApplicationRecord
  belongs_to :workspace
  belongs_to :subscription

  enum :status,  { pending: 0, completed: 1, failed: 2, refunded: 3 }
  enum :gateway, { vnpay: 0, momo: 1, stripe: 2, payos: 3 }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :gateway, presence: true

  def amount_formatted
    if currency == "VND"
      "#{amount_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫"
    else
      "$#{(amount_cents / 100.0).round(2)}"
    end
  end
end
