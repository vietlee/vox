class AddSourceDocumentTextToContentOutlines < ActiveRecord::Migration[7.2]
  def change
    add_column :content_outlines, :source_document_text, :text
  end
end
