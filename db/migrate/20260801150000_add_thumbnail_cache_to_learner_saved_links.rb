class AddThumbnailCacheToLearnerSavedLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :learner_saved_links, :thumbnail_data,  :text
    add_column :learner_saved_links, :thumbnail_token, :string
    add_index  :learner_saved_links, :thumbnail_token, unique: true
  end
end
