class AddConditionalLogicToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :conditional_logic, :jsonb, default: {}, null: false
  end
end
