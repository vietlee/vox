class CreateAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_logs do |t|
      t.references  :workspace,      foreign_key: true
      t.references  :user,           foreign_key: true
      t.string      :action,         null: false
      t.string      :resource_type
      t.integer     :resource_id
      t.jsonb       :changes_data,   default: {}
      t.string      :ip_address
      t.string      :user_agent
      t.timestamps
    end
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
  end
end
