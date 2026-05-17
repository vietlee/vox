class CreateWorkspaceMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :workspace_memberships do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, default: 0, null: false    # 0=supporter, 1=admin
      t.integer :status, default: 0, null: false  # 0=active, 1=inactive

      t.timestamps
    end

    add_index :workspace_memberships, [:workspace_id, :user_id], unique: true
  end
end
