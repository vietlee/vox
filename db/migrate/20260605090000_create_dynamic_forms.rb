class CreateDynamicForms < ActiveRecord::Migration[7.2]
  def change
    create_table :dynamic_forms do |t|
      t.references :workspace,  null: false, foreign_key: true
      t.references :user,       null: false, foreign_key: true
      t.string  :title,         null: false
      t.text    :description
      t.string  :slug,          null: false
      t.integer :status,        null: false, default: 0  # 0=active 1=closed
      t.integer :submissions_count, null: false, default: 0
      t.timestamps
    end
    add_index :dynamic_forms, [:workspace_id, :slug], unique: true
    add_index :dynamic_forms, :slug, unique: true

    create_table :dynamic_form_fields do |t|
      t.references :dynamic_form, null: false, foreign_key: true
      t.string  :label,       null: false
      t.string  :field_key,   null: false
      t.string  :field_type,  null: false, default: "text"
      t.string  :placeholder
      t.text    :hint
      t.boolean :required,    null: false, default: false
      t.jsonb   :options,     null: false, default: []   # [{label:, value:}]
      t.integer :min_length
      t.integer :max_length
      t.string  :min_value
      t.string  :max_value
      t.integer :position,    null: false, default: 0
      t.timestamps
    end

    create_table :dynamic_form_submissions do |t|
      t.references :dynamic_form, null: false, foreign_key: true
      t.jsonb   :data,            null: false, default: {}
      t.string  :respondent_token
      t.string  :ip_address
      t.timestamps
    end
  end
end
