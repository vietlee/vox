class CreateSurveys < ActiveRecord::Migration[7.2]
  def change
    create_table :surveys do |t|
      t.references  :workspace,     null: false, foreign_key: true
      t.references  :user,          null: false, foreign_key: true
      t.string      :title,          null: false
      t.text        :description
      t.string      :banner_image
      t.integer     :status,         null: false, default: 0
      t.integer     :identity_mode,  null: false, default: 0
      t.datetime    :starts_at
      t.datetime    :ends_at
      t.integer     :max_responses
      t.integer     :max_per_user,   default: 1
      t.boolean     :show_progress,  default: true
      t.boolean     :show_results,   default: false
      t.boolean     :allow_edit,     default: false
      t.string      :thank_you_message
      t.string      :redirect_url
      t.boolean     :scoring_enabled, default: false
      t.string      :slug
      t.integer     :response_count, default: 0
      t.jsonb       :settings,       default: {}
      t.boolean     :ai_generated,   default: false
      t.timestamps
    end
    add_index :surveys, :slug, unique: true
    add_index :surveys, :status
  end
end
