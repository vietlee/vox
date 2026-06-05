class AddAttachmentsToDynamicFormSubmissions < ActiveRecord::Migration[7.2]
  def change
    # ActiveStorage handles its own tables; we just need the has_many_attached declaration
    # Nothing to migrate here — ActiveStorage tables already exist
  end
end
