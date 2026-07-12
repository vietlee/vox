class LearnerSavedLink < ApplicationRecord
  belongs_to :learner

  CATEGORIES = %w[learning entertainment].freeze

  validates :url, presence: true
  validates :category, inclusion: { in: CATEGORIES }

  before_save :detect_link_type

  def self.infer_type(url)
    host = URI.parse(url.to_s.strip).host.to_s.downcase.gsub(/\Awww\./, '')
    case host
    when /youtube\.com/, /youtu\.be/ then 'youtube'
    when /facebook\.com/, /fb\.watch/ then 'facebook'
    when /vimeo\.com/ then 'vimeo'
    when /tiktok\.com/ then 'tiktok'
    else 'generic'
    end
  rescue
    'generic'
  end

  def embed_url
    case link_type
    when 'youtube'
      vid = url.match(/(?:v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/)&.[](1)
      "https://www.youtube.com/embed/#{vid}?autoplay=1&enablejsapi=1" if vid
    when 'vimeo'
      vid = url.match(/vimeo\.com\/(\d+)/)&.[](1)
      "https://player.vimeo.com/video/#{vid}?autoplay=1" if vid
    end
  end

  def embeddable?
    embed_url.present?
  end

  private

  def detect_link_type
    self.link_type = self.class.infer_type(url)
  end
end
