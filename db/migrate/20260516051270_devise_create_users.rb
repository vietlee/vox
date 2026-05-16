class DeviseCreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.references  :workspace,     foreign_key: true
      t.string      :email,          null: false, default: ""
      t.string      :encrypted_password, null: false, default: ""
      t.string      :name,           null: false, default: ""
      t.integer     :role,           null: false, default: 0
      t.integer     :status,         null: false, default: 0
      t.string      :avatar
      t.string      :reset_password_token
      t.datetime    :reset_password_sent_at
      t.datetime    :remember_created_at
      t.integer     :sign_in_count, default: 0, null: false
      t.datetime    :current_sign_in_at
      t.datetime    :last_sign_in_at
      t.string      :current_sign_in_ip
      t.string      :last_sign_in_ip
      t.string      :confirmation_token
      t.datetime    :confirmed_at
      t.datetime    :confirmation_sent_at
      t.string      :unconfirmed_email
      t.integer     :failed_attempts, default: 0, null: false
      t.string      :unlock_token
      t.datetime    :locked_at
      t.boolean     :must_change_password, default: false
      t.string      :otp_secret
      t.integer     :consumed_timestep
      t.boolean     :otp_required_for_login, default: false
      t.string      :otp_backup_codes, array: true
      t.timestamps null: false
    end

    add_index :users, :email
    add_index :users, [:workspace_id, :email], unique: true
    add_index :users, :reset_password_token, unique: true
    add_index :users, :confirmation_token, unique: true
    add_index :users, :unlock_token, unique: true
    add_index :users, :role
  end
end
