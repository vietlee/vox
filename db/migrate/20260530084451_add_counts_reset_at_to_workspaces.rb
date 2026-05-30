class AddCountsResetAtToWorkspaces < ActiveRecord::Migration[7.2]
  def change
    add_column :workspaces, :counts_reset_at, :datetime
  end
end
