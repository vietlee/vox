class DynamicFormAssignment < ApplicationRecord
  belongs_to :dynamic_form
  belongs_to :user
  validates :user_id, uniqueness: { scope: :dynamic_form_id }
end
