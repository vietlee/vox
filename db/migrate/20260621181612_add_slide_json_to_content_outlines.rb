class AddSlideJsonToContentOutlines < ActiveRecord::Migration[7.2]
  def change
    add_column :content_outlines, :slide_json, :text
  end
end
