class CreateAiModelConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_model_configs do |t|
      t.string :feature_key, null: false
      t.string :model_id,    null: false
      t.timestamps
    end
    add_index :ai_model_configs, :feature_key, unique: true
  end
end
