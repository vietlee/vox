class CreateContentTools < ActiveRecord::Migration[7.2]
  def change
    # Tóm tắt tài liệu
    create_table :document_summaries do |t|
      t.references :workspace,   null: false, foreign_key: true
      t.references :created_by,  null: false, foreign_key: { to_table: :users }
      t.string  :title
      t.string  :source_type    # 'pdf', 'audio', 'text'
      t.string  :source_filename
      t.text    :source_text    # extracted text
      t.text    :summary        # AI summary
      t.text    :key_points     # JSON array
      t.integer :status, default: 0  # 0=pending, 1=done, 2=failed
      t.timestamps
    end

    # Slide/Outline
    create_table :content_outlines do |t|
      t.references :workspace,  null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string  :title,      null: false
      t.string  :subject
      t.string  :output_type   # 'outline', 'slide_script', 'lesson_plan'
      t.text    :prompt_input  # user input
      t.text    :content       # AI generated content (HTML/markdown)
      t.integer :status, default: 0
      t.timestamps
    end
  end
end
