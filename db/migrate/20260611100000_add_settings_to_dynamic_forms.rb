class AddSettingsToDynamicForms < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_forms, :settings, :jsonb, default: {}, null: false
  end
end
