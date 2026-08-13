# One learner's tuition obligation for one class in one billing period.
# Marking it paid also books an income entry into the finance ledger.
class TuitionPayment < ApplicationRecord
  belongs_to :workspace
  belongs_to :learner_folder
  belongs_to :learner
  has_many :finance_entries, dependent: :nullify

  enum :status, { unpaid: 0, paid: 1 }

  validates :period_key, presence: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }

  scope :for_period, ->(key) { where(period_key: key) }

  # ── Period-key helpers ──────────────────────────────────────────────────
  # Monthly → "2026-08"; Quarterly → "2026-Q3".
  def self.month_key(date = Date.current) = date.strftime("%Y-%m")
  def self.quarter_key(date = Date.current) = "#{date.year}-Q#{((date.month - 1) / 3) + 1}"
  def self.key_for(cycle, date = Date.current)
    cycle.to_s == "quarterly" ? quarter_key(date) : month_key(date)
  end

  def self.period_label(key)
    if key.include?("-Q")
      y, q = key.split("-Q"); "Quý #{q}/#{y}"
    else
      y, m = key.split("-"); "Tháng #{m.to_i}/#{y}"
    end
  end

  def mark_paid!(on: Date.current, by: nil)
    transaction do
      update!(status: :paid, paid_on: on)
      unless finance_entries.exists?
        FinanceEntry.create!(
          workspace: workspace, kind: :income, amount_cents: amount_cents,
          occurred_on: on, category: "Học phí", source: :tuition,
          learner_folder: learner_folder, learner: learner, tuition_payment: self,
          created_by: by,
          note: "#{learner.name} · #{learner_folder.name} · #{self.class.period_label(period_key)}"
        )
      end
    end
  end

  def mark_unpaid!
    transaction do
      finance_entries.destroy_all
      update!(status: :unpaid, paid_on: nil)
    end
  end
end
