class LearningPath < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_many :learning_path_items,       -> { order(:position) }, dependent: :destroy
  has_many :learning_path_assignments, dependent: :destroy

  enum :status, { draft: 0, published: 1 }

  def completion_rate_for(user)
    assignment = learning_path_assignments.find_by(assignee: user)
    return nil unless assignment
    total = learning_path_items.count
    return 0 if total == 0
    done = assignment.learning_item_progresses.completed.count
    (done * 100.0 / total).round
  end
end
