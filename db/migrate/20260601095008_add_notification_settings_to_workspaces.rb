class AddNotificationSettingsToWorkspaces < ActiveRecord::Migration[7.2]
  def change
    add_column :workspaces, :notify_on_new_feedback, :boolean, default: false, null: false
    add_column :workspaces, :notify_on_new_response, :boolean, default: false, null: false
  end
end
