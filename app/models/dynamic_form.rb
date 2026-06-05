class DynamicForm < ApplicationRecord
  belongs_to :workspace
  belongs_to :user

  has_one_attached :logo
  has_many :dynamic_form_fields,      -> { order(:position) }, dependent: :destroy
  has_many :dynamic_form_submissions, dependent: :destroy
  has_one  :qr_code, as: :resource,   dependent: :destroy
  has_many :dynamic_form_assignments, dependent: :destroy
  has_many :assignees, through: :dynamic_form_assignments, source: :user

  # All users who should receive submission notifications (assignees + workspace owner)
  def notification_recipients
    (assignees + [workspace.users.first]).uniq.compact
  end

  enum :status, { draft: 0, active: 1, closed: 2 }

  validate :cannot_delete_active, on: :destroy

  def deletable?
    draft? || closed?
  end

  validates :title, presence: true, length: { maximum: 200 }
  validates :slug,  presence: true, uniqueness: { scope: :workspace_id },
                    format: { with: /\A[a-z0-9\-]+\z/ }

  before_validation :generate_slug, on: :create
  after_create      :create_qr_code!

  FIELD_TYPES = %w[text email number phone url date textarea select radio checkboxes file].freeze

  def public_url
    "/forms/#{slug}"
  end

  private

  def cannot_delete_active
    errors.add(:base, "Không thể xoá form đang mở. Hãy đóng form trước.") if active?
  end

  def generate_slug
    return if slug.present?
    base = title.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                .downcase.gsub(/[^a-z0-9\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-").gsub(/\A-|-\z/, "")
                .truncate(40, omission: "")
    base = "form" if base.blank?
    candidate = base
    n = 1
    while DynamicForm.exists?(workspace_id: workspace_id, slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end

  def create_qr_code!
    QrCode.create!(workspace: workspace, resource: self)
  end
end
