class AddDynamicFormsCountToWorkspaces < ActiveRecord::Migration[7.2]
  def change
    add_column :workspaces, :dynamic_forms_created_count, :integer, default: 0, null: false
  end
end
