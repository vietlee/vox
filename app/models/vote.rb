class Vote < ApplicationRecord
  include Sluggable
  belongs_to :workspace
  belongs_to :user
  has_many   :vote_options,    -> { order(:position) }, dependent: :destroy
  has_many   :vote_responses,  dependent: :destroy
  has_one    :qr_code,         as: :resource, dependent: :destroy

  enum :vote_type,     { single_choice: 0, multiple_choice: 1, word_cloud: 2, open_ended: 3, ranking: 4, qa_upvote: 5 }
  enum :status,        { draft: 0, active: 1, closed: 2 }
  enum :identity_mode, { anonymous: 0, email_required: 1, sso_required: 2 }

  # login_providers: "google", "microsoft", "both"
  LOGIN_PROVIDERS = %w[google microsoft both].freeze

  validates :title,           presence: true, length: { maximum: 300 }
  validates :login_providers, inclusion: { in: LOGIN_PROVIDERS }, allow_nil: true

  def login_required?
    sso_required?
  end

  def effective_login_providers
    login_providers.presence || "both"
  end

  def requires_google?
    sso_required? && effective_login_providers.in?(%w[google both])
  end

  def requires_microsoft?
    sso_required? && effective_login_providers.in?(%w[microsoft both])
  end

  before_create :generate_slug
  after_create  :generate_qr_code

  def open!
    raise "Cannot reopen a closed vote" if closed?
    update!(status: :active, opened_at: Time.current)
    broadcast_status_change
    schedule_auto_close if countdown_seconds.to_i > 0
  end

  def seconds_remaining
    return nil unless countdown_seconds.to_i > 0 && active? && opened_at
    remaining = countdown_seconds - (Time.current - opened_at).to_i
    [remaining, 0].max
  end

  def close!
    update!(status: :closed)
    broadcast_status_change
  end

  def results_by_option
    vote_options.map do |opt|
      { id: opt.id, label: opt.label, count: opt.votes_count, percentage: total_votes > 0 ? (opt.votes_count.to_f / total_votes * 100).round(1) : 0 }
    end
  end

  def total_votes
    vote_options.sum(:votes_count)
  end

  private

  def generate_slug
    base = self.class.slugify(title)
    self.slug = "#{base}-#{SecureRandom.hex(4)}"
  end

  def generate_qr_code
    QrCode.create!(workspace: workspace, resource: self, token: SecureRandom.urlsafe_base64(12))
  end

  def schedule_auto_close
    AutoCloseVoteJob.set(wait: countdown_seconds.seconds).perform_later(id, opened_at.to_i)
  end

  def broadcast_status_change
    ActionCable.server.broadcast("vote_#{id}", { type: "status_change", status: status })
  end
end
