class AddAdminEditableToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :admin_editable, :boolean, default: false, null: false
  end
end
