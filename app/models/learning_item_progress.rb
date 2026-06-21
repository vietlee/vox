class LearningItemProgress < ApplicationRecord
  belongs_to :learning_path_assignment
  belongs_to :learning_path_item

  enum :status, { not_started: 0, in_progress: 1, completed: 2 }
end
