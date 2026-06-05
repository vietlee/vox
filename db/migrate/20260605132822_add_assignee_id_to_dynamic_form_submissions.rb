class AddAssigneeIdToDynamicFormSubmissions < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_submissions, :assignee_id, :integer
    add_index  :dynamic_form_submissions, :assignee_id
  end
end
