class Question < ApplicationRecord
  belongs_to :survey
  has_many   :question_options, -> { order(:position) }, dependent: :destroy
  has_many   :answers, dependent: :destroy

  enum :question_type, {
    single_choice:   0,
    multiple_choice: 1,
    rating:          2,
    short_text:      3,
    long_text:       4,
    dropdown:        5,
    linear_scale:    6,
    matrix:          7,
    date_time:       8,
    file_upload:     9,
    nps:             10
  }

  validates :title, presence: true
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def choice_type?
    single_choice? || multiple_choice? || dropdown?
  end

  def text_type?
    short_text? || long_text?
  end

  def numeric_type?
    rating? || linear_scale? || nps?
  end
end
