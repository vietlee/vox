class CreateLearners < ActiveRecord::Migration[7.2]
  def change
    create_table :learners do |t|
      t.string   :email,                  null: false, default: ""
      t.string   :name,                   null: false, default: ""
      t.string   :encrypted_password,     null: false, default: ""
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email
      t.integer  :sign_in_count,          default: 0, null: false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip
      t.integer  :credits,                default: 50, null: false
      t.string   :invite_token
      t.datetime :invite_sent_at
      t.boolean  :password_set,           default: false, null: false
      t.timestamps
    end

    add_index :learners, :email,                unique: true
    add_index :learners, :reset_password_token, unique: true
    add_index :learners, :confirmation_token,   unique: true
    add_index :learners, :invite_token,         unique: true
  end
end
