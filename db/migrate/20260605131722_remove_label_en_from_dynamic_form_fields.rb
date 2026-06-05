class RemoveLabelEnFromDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    remove_column :dynamic_form_fields, :label_en, :string
  end
end
