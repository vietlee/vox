class AddAdminOnlyToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :admin_only, :boolean, default: false, null: false
  end
end
