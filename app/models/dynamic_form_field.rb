class DynamicFormField < ApplicationRecord
  belongs_to :dynamic_form

  TYPES = DynamicForm::FIELD_TYPES

  validates :label,      presence: true, length: { maximum: 200 }
  validates :field_key,  presence: true,
                         format: { with: /\A[a-z0-9_]+\z/, message: "chỉ gồm chữ thường, số, dấu _" }
  validates :field_type, inclusion: { in: TYPES }

  before_validation :sanitize_field_key

  # Returns label in current locale, falls back to default label
  def localized_label
    if I18n.locale.to_s == "en" && label_en.present?
      label_en
    else
      label
    end
  end

  # Types that support options list
  def option_type?
    %w[select radio checkboxes].include?(field_type)
  end

  # Parse options array of hashes [{label:, value:}]
  def options_list
    Array(options).map { |o| o.is_a?(Hash) ? o.transform_keys(&:to_s) : { "label" => o.to_s, "value" => o.to_s } }
  end

  private

  def sanitize_field_key
    if label.present? && field_key.blank?
      self.field_key = label.parameterize(separator: "_").gsub(/-/, "_").gsub(/[^a-z0-9_]/, "")
    end
    self.field_key = field_key.to_s.downcase.gsub(/[^a-z0-9_]/, "_").gsub(/_+/, "_").gsub(/\A_|_\z/, "")
  end
end
