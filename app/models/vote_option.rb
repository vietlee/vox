class VoteOption < ApplicationRecord
  belongs_to :vote

  validates :label, presence: true
  validates :position, numericality: { greater_than_or_equal_to: 0 }
end
