class CreateQrCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :qr_codes do |t|
      t.references  :workspace,      null: false, foreign_key: true
      t.string      :resource_type,  null: false
      t.integer     :resource_id,    null: false
      t.string      :token,          null: false
      t.string      :foreground_color, default: "#000000"
      t.string      :background_color, default: "#FFFFFF"
      t.boolean     :show_logo,      default: false
      t.integer     :scan_count,     default: 0
      t.timestamps
    end
    add_index :qr_codes, :token, unique: true
    add_index :qr_codes, [:resource_type, :resource_id], unique: true
  end
end
