class AddFileAttrsToDynamicFormFields < ActiveRecord::Migration[7.2]
  def change
    add_column :dynamic_form_fields, :accept,      :string   # e.g. "image/*,.pdf"
    add_column :dynamic_form_fields, :max_size_mb, :integer  # max file size in MB
  end
end
