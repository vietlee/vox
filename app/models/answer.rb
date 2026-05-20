class Answer < ApplicationRecord
  belongs_to :response
  belongs_to :question

  has_one_attached :uploaded_file

  validates :response, :question, presence: true

  def value
    case question.question_type.to_sym
    when :short_text, :long_text then text_value
    when :rating, :linear_scale, :nps then numeric_value
    when :single_choice, :dropdown then option_ids&.first
    when :multiple_choice then option_ids
    when :matrix then matrix_values
    when :date_time then date_value
    when :file_upload then uploaded_file.attached? ? uploaded_file.filename.to_s : nil
    else text_value
    end
  end

  def file_url
    return nil unless uploaded_file.attached?
    Rails.application.routes.url_helpers.rails_blob_url(uploaded_file, only_path: true)
  end
end
