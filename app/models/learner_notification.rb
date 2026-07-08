class LearnerNotification < ApplicationRecord
  belongs_to :learner

  TYPES = %w[quiz_assigned flashcard_assigned path_assigned badge_earned general].freeze

  scope :unread, -> { where(read: false) }
  scope :recent, -> { order(created_at: :desc) }

  def self.notify!(learner:, title:, body: nil, type: "general", action_url: nil)
    create!(learner: learner, title: title, body: body, notification_type: type, action_url: action_url)
  end
end
