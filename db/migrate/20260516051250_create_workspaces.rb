class CreateWorkspaces < ActiveRecord::Migration[7.2]
  def change
    create_table :workspaces do |t|
      t.string   :name,             null: false
      t.string   :slug,             null: false
      t.string   :logo
      t.string   :brand_color,      default: "#6366F1"
      t.string   :favicon
      t.string   :language,         default: "vi"
      t.string   :timezone,         default: "Asia/Ho_Chi_Minh"
      t.integer  :status,           default: 0, null: false
      t.string   :custom_domain
      t.jsonb    :email_template_config, default: {}
      t.boolean  :force_2fa,        default: false
      t.integer  :session_timeout_days, default: 60
      t.timestamps
    end

    add_index :workspaces, :slug, unique: true
    add_index :workspaces, :status
  end
end
