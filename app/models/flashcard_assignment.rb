class FlashcardAssignment < ApplicationRecord
  belongs_to :flashcard_deck
  belongs_to :learner
  belongs_to :assigned_by, class_name: "User"

  enum :status, { pending: 0, in_progress: 1, completed: 2 }

  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create

  def overdue?
    due_at.present? && due_at < Time.current && !completed?
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(20)
  end
end
