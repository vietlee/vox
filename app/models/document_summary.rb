class DocumentSummary < ApplicationRecord
  belongs_to :workspace
  belongs_to :created_by, class_name: "User"
  has_one_attached :source_file

  enum :status, { pending: 0, done: 1, failed: 2 }

  MAX_FILE_SIZE = 20.megabytes

  validates :source_type, inclusion: { in: %w[pdf docx doc txt csv xlsx xls pptx image text] }
  validate :file_size_within_limit

  private

  def file_size_within_limit
    return unless source_file.attached? && source_file.blob.byte_size > MAX_FILE_SIZE
    errors.add(:source_file, "quá lớn (tối đa #{MAX_FILE_SIZE / 1.megabyte}MB)")
  end
end
