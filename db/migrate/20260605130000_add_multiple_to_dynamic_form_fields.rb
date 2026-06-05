class AddMultipleToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :multiple, :boolean, null: false, default: false
  end
end
