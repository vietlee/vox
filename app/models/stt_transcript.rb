class SttTranscript < ApplicationRecord
  belongs_to :workspace

  validates :title,           presence: true
  validates :transcript_text, presence: true
  validates :source, inclusion: { in: %w[file url mic] }

  scope :recent, -> { order(created_at: :desc) }

  # Concise display title: strip long URLs to just the domain
  def display_title
    return title unless source == "url" && title.start_with?("http")
    URI.parse(title).host rescue title
  end
end
