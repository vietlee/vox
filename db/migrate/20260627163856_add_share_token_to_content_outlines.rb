class AddShareTokenToContentOutlines < ActiveRecord::Migration[7.2]
  def change
    add_column :content_outlines, :share_token, :string
    add_index :content_outlines, :share_token, unique: true
    ContentOutline.find_each do |co|
      co.update_column(:share_token, SecureRandom.urlsafe_base64(12)) if co.share_token.blank?
    end
  end
end
