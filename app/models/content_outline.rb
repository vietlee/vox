class ContentOutline < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"

  enum :status, { pending: 0, done: 1, failed: 2 }
  TYPES = %w[outline slide_script lesson_plan].freeze

  has_one_attached :pptx_file
  has_many_attached :slide_images
  has_many_attached :edit_images

  before_create :generate_share_token

  def generate_share_token
    self.share_token ||= SecureRandom.urlsafe_base64(12)
  end

  def regenerate_share_token!
    update!(share_token: SecureRandom.urlsafe_base64(12))
  end
end
