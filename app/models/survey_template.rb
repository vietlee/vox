class SurveyTemplate < ApplicationRecord
  validates :title, :template_type, :category, presence: true

  scope :active,    -> { where(active: true) }
  scope :ordered,   -> { order(:position, :id) }
  scope :surveys,   -> { where(template_type: "survey") }
  scope :votes,     -> { where(template_type: "vote") }
  scope :feedbacks, -> { where(template_type: "feedback") }

  TYPES = %w[survey vote feedback].freeze
  CATEGORIES = %w[hr customer education event marketing product general].freeze

  CATEGORY_META = {
    "hr"        => { vi: "Nhân sự & HR",        en: "HR & People",          icon: "👥", color: "violet" },
    "customer"  => { vi: "Khách hàng",           en: "Customer",             icon: "⭐", color: "amber"  },
    "education" => { vi: "Giáo dục",             en: "Education",            icon: "📚", color: "sky"    },
    "event"     => { vi: "Sự kiện",              en: "Events",               icon: "🎉", color: "pink"   },
    "marketing" => { vi: "Marketing",            en: "Marketing",            icon: "📈", color: "emerald"},
    "product"   => { vi: "Sản phẩm",             en: "Product",              icon: "🚀", color: "indigo" },
    "general"   => { vi: "Tổng hợp",             en: "General",              icon: "📋", color: "slate"  },
  }.freeze

  TYPE_META = {
    "survey"   => { vi: "Khảo sát", en: "Survey",        icon: "📋", color: "indigo" },
    "vote"     => { vi: "Bình chọn", en: "Vote",          icon: "🗳️", color: "violet" },
    "feedback" => { vi: "Góp ý",    en: "Feedback Board", icon: "💬", color: "emerald"},
  }.freeze

  def questions_data
    structure["questions"] || []
  end

  def options_data
    structure["options"] || []
  end

  def question_count
    case template_type
    when "survey"   then questions_data.size
    when "vote"     then options_data.size
    when "feedback" then 0
    end
  end

  def category_label(locale = I18n.locale)
    meta = CATEGORY_META[category] || {}
    meta[locale.to_sym] || meta[:vi] || category.humanize
  end

  def category_icon
    CATEGORY_META.dig(category, :icon) || "📋"
  end

  def type_label(locale = I18n.locale)
    meta = TYPE_META[template_type] || {}
    meta[locale.to_sym] || meta[:vi] || template_type.humanize
  end

  def type_color
    TYPE_META.dig(template_type, :color) || "indigo"
  end
end
