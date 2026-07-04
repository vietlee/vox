class LearnerFolderMember < ApplicationRecord
  belongs_to :learner_folder
  belongs_to :learner

  validates :learner_id, uniqueness: { scope: :learner_folder_id }
end
