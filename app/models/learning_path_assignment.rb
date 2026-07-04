class LearningPathAssignment < ApplicationRecord
  belongs_to :learning_path
  belongs_to :assigned_by, class_name: "User"
  belongs_to :assignee,    class_name: "User",    optional: true
  belongs_to :learner,                             optional: true
  has_many :learning_item_progresses, dependent: :destroy

  enum :status, { active: 0, completed: 1, cancelled: 2 }

  validates :token, uniqueness: true, allow_nil: true

  before_validation :generate_token, on: :create

  def overdue?
    due_date.present? && due_date < Date.current && status != "completed"
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(20) if learner_id.present?
  end

  def progress_pct
    items = learning_path.learning_path_items
    total = items.loaded? ? items.size : items.count
    return 0 if total == 0
    done = learning_item_progresses.loaded? ? learning_item_progresses.count(&:completed?) : learning_item_progresses.completed.count
    (done * 100.0 / total).round
  end
end
