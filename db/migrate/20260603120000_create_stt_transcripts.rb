class CreateSttTranscripts < ActiveRecord::Migration[7.2]
  def change
    create_table :stt_transcripts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string  :title,           null: false, default: "Untitled"
      t.text    :transcript_text, null: false, default: ""
      t.string  :language_code
      t.float   :duration_secs,   null: false, default: 0.0
      t.integer :credits_used,    null: false, default: 1
      t.string  :source,          null: false, default: "file"  # file | url | mic
      t.timestamps
    end
    add_index :stt_transcripts, [:workspace_id, :created_at]
  end
end
