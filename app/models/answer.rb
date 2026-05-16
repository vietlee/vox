class Answer < ApplicationRecord
  belongs_to :response
  belongs_to :question

  validates :response, :question, presence: true

  def value
    case question.question_type.to_sym
    when :short_text, :long_text then text_value
    when :rating, :linear_scale, :nps then numeric_value
    when :multiple_choice, :dropdown then option_ids&.first
    when :checkbox then option_ids
    when :matrix then matrix_values
    when :date_time then date_value
    else text_value
    end
  end
end
