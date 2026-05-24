class CreateSurveyTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :survey_templates do |t|
      t.string  :title,             null: false
      t.text    :description
      t.string  :category,          null: false, default: "general"
      t.string  :template_type,     null: false, default: "survey"
      t.string  :icon,              default: "📋"
      t.string  :color,             default: "#4F46E5"
      t.integer :estimated_minutes, default: 3
      t.integer :use_count,         default: 0, null: false
      t.boolean :active,            default: true, null: false
      t.integer :position,          default: 0, null: false
      t.jsonb   :structure,         default: {}, null: false
      t.timestamps
    end
    add_index :survey_templates, :template_type
    add_index :survey_templates, :active
    add_index :survey_templates, :position
  end
end
