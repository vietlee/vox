class ShortLink < ApplicationRecord
  belongs_to :workspace, optional: true

  validates :code, presence: true, uniqueness: true
  validates :target_url, presence: true

  CHARS = ("a".."z").to_a + ("0".."9").to_a

  def self.for_url(url, workspace: nil)
    find_or_create_by!(target_url: url) do |sl|
      sl.workspace = workspace
      sl.code      = generate_code
    end
  end

  def self.generate_code(len = 6)
    loop do
      code = Array.new(len) { CHARS.sample }.join
      return code unless exists?(code: code)
    end
  end

  def increment_clicks!
    increment!(:clicks_count)
  end
end
