class FeedbackBoard < ApplicationRecord
  include Sluggable
  belongs_to :workspace
  belongs_to :user
  has_many   :feedbacks,    dependent: :destroy
  has_many   :action_items, dependent: :destroy
  has_one    :qr_code,    as: :resource, dependent: :destroy
  has_one_attached :logo

  enum :status,        { active: 0, closed: 1, archived: 2 }
  enum :identity_mode, { anonymous: 0, public_identity: 1, user_choice: 2 }

  validates :title, presence: true, length: { maximum: 200 }

  before_create :generate_slug
  after_create  :generate_qr_code

  private

  def generate_slug
    base = self.class.slugify(title)
    self.slug = "#{base}-#{SecureRandom.hex(4)}"
  end

  def generate_qr_code
    QrCode.create!(workspace: workspace, resource: self, token: SecureRandom.urlsafe_base64(12))
  end
end
