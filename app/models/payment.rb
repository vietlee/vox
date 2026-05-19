class Payment < ApplicationRecord
  belongs_to :workspace
  belongs_to :subscription
  belongs_to :addon_config, optional: true

  enum :status,  { pending: 0, completed: 1, failed: 2, refunded: 3 }
  enum :gateway, { vnpay: "vnpay", momo: "momo", stripe: "stripe", payos: "payos" }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :gateway, presence: true

  GATEWAY_LABELS = {
    "payos"  => "QR Code (PayOS)",
    "vnpay"  => "VNPay",
    "momo"   => "MoMo",
    "stripe" => "Stripe"
  }.freeze

  def gateway_label
    GATEWAY_LABELS[gateway] || gateway&.upcase || "—"
  end

  def description_label
    if addon_config.present?
      addon_config.name
    elsif subscription.present?
      "#{I18n.t('subscription.plan_label')} #{subscription.plan&.upcase}"
    else
      "—"
    end
  end

  def amount_formatted
    if currency == "VND"
      "#{amount_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫"
    else
      "$#{(amount_cents / 100.0).round(2)}"
    end
  end
end
