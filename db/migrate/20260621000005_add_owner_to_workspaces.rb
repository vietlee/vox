class AddOwnerToWorkspaces < ActiveRecord::Migration[7.2]
  def change
    add_column :workspaces, :owner_id, :bigint
    add_index  :workspaces, :owner_id

    # Backfill: set owner_id = user who has workspace_id = this workspace
    execute <<~SQL
      UPDATE workspaces w
      SET owner_id = (SELECT id FROM users u WHERE u.workspace_id = w.id LIMIT 1)
    SQL
  end
end
