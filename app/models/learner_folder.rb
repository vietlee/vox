class LearnerFolder < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_many :learner_folder_members, dependent: :destroy
  has_many :learners, through: :learner_folder_members

  validates :name, presence: true

  def member_count
    learner_folder_members.count
  end
end
