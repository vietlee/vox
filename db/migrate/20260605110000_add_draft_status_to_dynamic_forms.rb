class AddDraftStatusToDynamicForms < ActiveRecord::Migration[7.2]
  def up
    # Old: 0=active, 1=closed
    # New: 0=draft, 1=active, 2=closed
    execute "UPDATE dynamic_forms SET status = 2 WHERE status = 1"  # closed → 2
    execute "UPDATE dynamic_forms SET status = 1 WHERE status = 0"  # active → 1
    change_column_default :dynamic_forms, :status, 0                # default = draft
  end

  def down
    change_column_default :dynamic_forms, :status, 0
    execute "UPDATE dynamic_forms SET status = 0 WHERE status = 1"
    execute "UPDATE dynamic_forms SET status = 1 WHERE status = 2"
  end
end
