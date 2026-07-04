class AddUserIdToSubscriptions < ActiveRecord::Migration[7.2]
  def up
    add_column :subscriptions, :user_id, :bigint
    add_index  :subscriptions, :user_id

    # Backfill: link each subscription to its workspace owner (PostgreSQL syntax)
    execute <<-SQL
      UPDATE subscriptions
      SET user_id = workspaces.owner_id
      FROM workspaces
      WHERE subscriptions.workspace_id = workspaces.id
        AND workspaces.owner_id IS NOT NULL
    SQL
  end

  def down
    remove_index  :subscriptions, :user_id
    remove_column :subscriptions, :user_id
  end
end
