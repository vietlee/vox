class AddUserIdToSubscriptions < ActiveRecord::Migration[7.2]
  def up
    add_column :subscriptions, :user_id, :bigint
    add_index  :subscriptions, :user_id

    # Backfill: link each subscription to its workspace owner
    execute <<-SQL
      UPDATE subscriptions
      INNER JOIN workspaces ON subscriptions.workspace_id = workspaces.id
      SET subscriptions.user_id = workspaces.owner_id
      WHERE workspaces.owner_id IS NOT NULL
    SQL
  end

  def down
    remove_index  :subscriptions, :user_id
    remove_column :subscriptions, :user_id
  end
end
