class DocumentSummary < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_one_attached :source_file

  enum :status, { pending: 0, done: 1, failed: 2 }
end
