class LearningPathAssignment < ApplicationRecord
  belongs_to :learning_path
  belongs_to :assigned_by, class_name: "User"
  belongs_to :assignee,    class_name: "User"
  has_many :learning_item_progresses, dependent: :destroy

  enum :status, { active: 0, completed: 1, cancelled: 2 }

  def progress_pct
    total = learning_path.learning_path_items.count
    return 0 if total == 0
    done = learning_item_progresses.completed.count
    (done * 100.0 / total).round
  end
end
