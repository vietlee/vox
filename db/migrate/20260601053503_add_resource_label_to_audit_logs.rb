class AddResourceLabelToAuditLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :audit_logs, :resource_label, :string
  end
end
