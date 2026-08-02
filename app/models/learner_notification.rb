class LearnerNotification < ApplicationRecord
  belongs_to :learner

  TYPES = %w[quiz_assigned flashcard_assigned path_assigned badge_earned general].freeze

  scope :unread, -> { where(read: false) }
  scope :recent, -> { order(created_at: :desc) }

  def self.notify!(learner:, title:, body: nil, type: "general", action_url: nil)
    create!(learner: learner, title: title, body: body, notification_type: type, action_url: action_url)
  end

  # Localized variant — renders title/body from `learner_notif.*` keys in the
  # learner's own language (falls back to Vietnamese).
  def self.notify_t!(learner:, title_key:, body_key: nil, body: nil, title_args: {}, body_args: {}, type: "general", action_url: nil)
    loc = learner.preferred_locale.presence || "vi"
    notify!(
      learner: learner,
      title:   I18n.t("learner_notif.#{title_key}", locale: loc, **title_args),
      body:    body || (body_key ? I18n.t("learner_notif.#{body_key}", locale: loc, **body_args) : nil),
      type:    type, action_url: action_url
    )
  end
end
