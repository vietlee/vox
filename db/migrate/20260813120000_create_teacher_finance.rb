class CreateTeacherFinance < ActiveRecord::Migration[7.2]
  def change
    # Per-class tuition plan (amount + billing cycle) used to generate the
    # per-period roster of who must pay.
    add_column :learner_folders, :tuition_amount_cents, :integer, default: 0, null: false
    add_column :learner_folders, :tuition_cycle, :integer, default: 0, null: false # 0 monthly, 1 quarterly

    # A learner's obligation to pay tuition for one class in one period.
    create_table :tuition_payments do |t|
      t.references :workspace,      null: false, foreign_key: true
      t.references :learner_folder, null: false, foreign_key: true
      t.references :learner,        null: false, foreign_key: true
      t.string  :period_key, null: false            # "2026-08" (month) or "2026-Q3" (quarter)
      t.integer :amount_cents, default: 0, null: false
      t.integer :status, default: 0, null: false     # 0 unpaid, 1 paid
      t.date    :paid_on
      t.string  :note
      t.timestamps
    end
    add_index :tuition_payments, [:learner_folder_id, :learner_id, :period_key],
              unique: true, name: "idx_tuition_unique_period"
    add_index :tuition_payments, [:workspace_id, :period_key]

    # Unified income/expense ledger for the teacher's workspace.
    create_table :finance_entries do |t|
      t.references :workspace, null: false, foreign_key: true
      t.integer :kind,   default: 0, null: false      # 0 income, 1 expense
      t.integer :amount_cents, default: 0, null: false
      t.date    :occurred_on, null: false
      t.string  :category
      t.text    :note
      t.integer :source, default: 0, null: false      # 0 manual, 1 ai_import, 2 tuition
      t.references :learner_folder, null: true, foreign_key: true
      t.references :learner,        null: true, foreign_key: true
      t.references :tuition_payment, null: true, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :finance_entries, [:workspace_id, :occurred_on]
    add_index :finance_entries, [:workspace_id, :kind]
  end
end
