class AddStatusToDynamicFormSubmissions < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_submissions, :status, :integer, default: 0, null: false
    add_index  :dynamic_form_submissions, :status
  end
end
