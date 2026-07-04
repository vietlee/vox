class CreateLearnerFolders < ActiveRecord::Migration[7.2]
  def change
    create_table :learner_folders do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false

      t.timestamps
    end

    create_table :learner_folder_members do |t|
      t.references :learner_folder, null: false, foreign_key: true
      t.references :learner, null: false, foreign_key: true
      t.timestamps
    end

    add_index :learner_folder_members, [:learner_folder_id, :learner_id], unique: true, name: "idx_learner_folder_members_unique"
  end
end
