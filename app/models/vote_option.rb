class VoteOption < ApplicationRecord
  belongs_to :vote
  has_one_attached :image

  default_scope { order(:position) }

  validates :label, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }

  def image_path
    return nil unless image.attached?
    Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true)
  end
end
