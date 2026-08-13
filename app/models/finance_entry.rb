# A single income or expense line in a teacher workspace's finance ledger.
# Income can be standalone (misc) or linked to a TuitionPayment.
class FinanceEntry < ApplicationRecord
  belongs_to :workspace
  belongs_to :learner_folder, optional: true
  belongs_to :learner, optional: true
  belongs_to :tuition_payment, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  enum :kind,   { income: 0, expense: 1 }
  enum :source, { manual: 0, ai_import: 1, tuition: 2 }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :occurred_on, presence: true

  scope :in_range, ->(from, to) { where(occurred_on: from..to) }
  scope :recent,   -> { order(occurred_on: :desc, id: :desc) }

  def amount_formatted
    "#{amount_cents.to_s.reverse.gsub(/\d{3}(?=.)/, '\0.').reverse} ₫"
  end
end
