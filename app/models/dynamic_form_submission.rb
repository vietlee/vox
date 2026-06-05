class DynamicFormSubmission < ApplicationRecord
  belongs_to :dynamic_form
  belongs_to :assignee, class_name: "User", optional: true

  has_many_attached :field_files

  enum :status, { pending: 0, processing: 1, done: 2 }, prefix: false

  validates :data, presence: true

  after_create :increment_counter

  scope :search_data, ->(q) {
    return all if q.blank?
    where("data::text ILIKE ?", "%#{q.gsub('%','').gsub('_','')}%")
  }

  def value_for(field_key)
    data[field_key.to_s]
  end

  private

  def increment_counter
    dynamic_form.increment!(:submissions_count)
  end
end
