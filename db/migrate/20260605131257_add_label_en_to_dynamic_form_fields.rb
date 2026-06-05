class AddLabelEnToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :label_en, :string
  end
end
