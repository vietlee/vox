class CreateDynamicFormAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :dynamic_form_assignments do |t|
      t.references :dynamic_form, null: false, foreign_key: true
      t.references :user,         null: false, foreign_key: true
      t.timestamps
    end
    add_index :dynamic_form_assignments, [:dynamic_form_id, :user_id], unique: true
  end
end
