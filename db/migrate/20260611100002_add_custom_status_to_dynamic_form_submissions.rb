class AddCustomStatusToDynamicFormSubmissions < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_submissions, :custom_status, :string
  end
end
