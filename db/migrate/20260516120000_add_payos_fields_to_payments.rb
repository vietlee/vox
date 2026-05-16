class AddPayosFieldsToPayments < ActiveRecord::Migration[7.2]
  def change
    add_column :payments, :payos_order_code, :bigint
    add_column :payments, :payment_link_id, :string
    add_index  :payments, :payos_order_code, unique: true, where: "payos_order_code IS NOT NULL"
  end
end
