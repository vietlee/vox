class Survey < ApplicationRecord
  belongs_to :workspace
  belongs_to :user
  has_many   :questions,         -> { order(:position) }, dependent: :destroy
  has_many   :responses,         dependent: :destroy
  has_many   :ai_analysis_results, as: :resource, dependent: :destroy
  has_one    :qr_code,           as: :resource, dependent: :destroy

  enum :status,        { draft: 0, active: 1, closed: 2, archived: 3 }
  enum :identity_mode, { anonymous: 0, email_required: 1, login_required: 2 }

  validates :title, presence: true, length: { maximum: 200 }
  validates :slug,  uniqueness: true, allow_blank: true

  before_create :generate_slug
  after_create  :generate_qr_code

  scope :active_now, -> { active.where("(starts_at IS NULL OR starts_at <= ?) AND (ends_at IS NULL OR ends_at >= ?)", Time.current, Time.current) }

  def published?
    active? || closed?
  end

  def accepting_responses?
    active? &&
      (starts_at.nil? || starts_at <= Time.current) &&
      (ends_at.nil? || ends_at >= Time.current) &&
      (max_responses.nil? || response_count < max_responses)
  end

  def completion_rate
    return 0 if responses.count == 0
    (responses.where(status: :completed).count.to_f / responses.count * 100).round(1)
  end

  def latest_ai_analysis
    ai_analysis_results.order(created_at: :desc).first
  end

  private

  def generate_slug
    base = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "").first(50)
    self.slug = "#{base}-#{SecureRandom.hex(4)}"
  end

  def generate_qr_code
    QrCode.create!(workspace: workspace, resource: self, token: SecureRandom.urlsafe_base64(12))
  end
end
