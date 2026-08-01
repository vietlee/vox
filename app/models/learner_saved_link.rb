require 'net/http'
require 'cgi'

class LearnerSavedLink < ApplicationRecord
  belongs_to :learner

  CATEGORIES = %w[learning entertainment].freeze

  # Hosts whose thumbnail URLs are signed and expire after a while (Facebook,
  # Instagram, TikTok CDNs). We must cache the actual bytes or the image dies.
  EXPIRING_THUMB = /fbcdn\.net|scontent|cdninstagram|tiktokcdn|\.tiktok\.com/i

  validates :url, presence: true
  validates :category, inclusion: { in: CATEGORIES }

  before_save   :detect_link_type
  after_commit  :cache_thumbnail_later, on: [:create, :update]

  def thumbnail_expiring?
    thumbnail.to_s.match?(EXPIRING_THUMB)
  end

  # Kicks off caching (and mints a capability token) for an expiring thumbnail.
  def cache_thumbnail_later
    return unless thumbnail_expiring?
    update_column(:thumbnail_token, SecureRandom.urlsafe_base64(16)) if thumbnail_token.blank?
    CacheSavedLinkThumbnailJob.perform_later(id) if thumbnail_data.blank?
  end

  # Re-scrape the page's og:image (used when the stored thumbnail URL has
  # already expired — Facebook mints a fresh signed URL each fetch).
  def self.scrape_og_image(page_url)
    uri = URI.parse(page_url)
    return nil unless %w[http https].include?(uri.scheme)
    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
    req['Accept'] = 'text/html,application/xhtml+xml'
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                          open_timeout: 6, read_timeout: 6) { |h| h.request(req) }
    return nil unless res.is_a?(Net::HTTPSuccess)
    html = res.body.to_s.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
    og = html[/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/im, 1] ||
         html[/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/im, 1]
    CGI.unescapeHTML(og.to_s.strip).presence
  rescue
    nil
  end

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
