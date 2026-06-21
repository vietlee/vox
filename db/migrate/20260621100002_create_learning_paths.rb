class CreateLearningPaths < ActiveRecord::Migration[7.2]
  def change
    create_table :learning_paths do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string  :title,       null: false
      t.text    :description
      t.string  :subject                  # môn học / chủ đề
      t.integer :status,      default: 0  # 0=draft, 1=published
      t.boolean :ai_generated, default: false
      t.timestamps
    end

    create_table :learning_path_items do |t|
      t.references :learning_path, null: false, foreign_key: true
      t.integer :item_type,   null: false  # 0=lesson, 1=quiz
      t.bigint  :quiz_set_id             # nếu item_type=quiz
      t.string  :title,       null: false
      t.text    :content                 # nội dung bài học (HTML)
      t.integer :position,    default: 0
      t.integer :estimated_minutes, default: 15
      t.timestamps
    end
    add_index :learning_path_items, [:learning_path_id, :position]

    create_table :learning_path_assignments do |t|
      t.references :learning_path, null: false, foreign_key: true
      t.references :assigned_by,   null: false, foreign_key: { to_table: :users }
      t.references :assignee,      null: false, foreign_key: { to_table: :users }
      t.date    :due_date
      t.integer :status, default: 0   # 0=active, 1=completed, 2=cancelled
      t.timestamps
    end
    add_index :learning_path_assignments, [:learning_path_id, :assignee_id], unique: true

    create_table :learning_item_progresses do |t|
      t.references :learning_path_assignment, null: false, foreign_key: true
      t.references :learning_path_item,       null: false, foreign_key: true
      t.integer :status, default: 0    # 0=not_started, 1=in_progress, 2=completed
      t.datetime :completed_at
      t.timestamps
    end
  end
end
