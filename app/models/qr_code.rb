class QrCode < ApplicationRecord
  belongs_to :workspace
  belongs_to :resource, polymorphic: true

  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  def url
    resource_url
  end

  def resource_url
    case resource_type
    when "Survey"        then "/s/#{resource.slug}"
    when "Vote"          then "/v/#{resource.slug}"
    when "FeedbackBoard" then "/f/#{resource.slug}"
    end
  end

  def increment_scan!
    increment!(:scan_count)
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(12)
  end
end
