class WorkspaceMembership < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  enum :role,   { supporter: 0, admin: 1 }
  enum :status, { active: 0, inactive: 1 }

  validates :user_id, uniqueness: { scope: :workspace_id }
end
