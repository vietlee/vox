require 'net/http'
require 'base64'

# Downloads a saved link's thumbnail and stores the bytes on our side, so
# expiring CDN URLs (Facebook/Instagram/TikTok) keep working forever. If the
# stored URL has already expired, re-scrapes the page for a fresh og:image.
class CacheSavedLinkThumbnailJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: 1 if respond_to?(:sidekiq_options)

  MAX_BYTES = 4_000_000

  def perform(link_id)
    link = LearnerSavedLink.find_by(id: link_id)
    return unless link&.thumbnail.present?

    bytes, ctype = fetch(link.thumbnail)

    # Stored URL dead → re-scrape the page for a fresh og:image and retry once.
    if bytes.nil?
      fresh = LearnerSavedLink.scrape_og_image(link.url)
      if fresh.present? && fresh != link.thumbnail
        link.update_column(:thumbnail, fresh)
        bytes, ctype = fetch(fresh)
      end
    end
    return if bytes.nil?

    link.update_column(:thumbnail_data, "data:#{ctype};base64,#{Base64.strict_encode64(bytes)}")
  rescue => e
    Rails.logger.warn "[CacheSavedLinkThumbnailJob] link #{link_id}: #{e.message}"
  end

  private

  def fetch(url, redirects: 3)
    return [nil, nil] if url.blank? || redirects < 0
    uri = URI.parse(url)
    return [nil, nil] unless %w[http https].include?(uri.scheme)

    req = Net::HTTP::Get.new(uri)
    req['User-Agent'] = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1'
    req['Accept'] = 'image/*'

    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                          open_timeout: 6, read_timeout: 8) { |h| h.request(req) }

    if res.is_a?(Net::HTTPRedirection) && res['location']
      return fetch(URI.join(url, res['location']).to_s, redirects: redirects - 1)
    end
    return [nil, nil] unless res.is_a?(Net::HTTPSuccess)

    ctype = res['content-type'].to_s.split(';').first.presence
    return [nil, nil] unless ctype&.start_with?('image/')

    body = res.body.to_s
    return [nil, nil] if body.empty? || body.bytesize > MAX_BYTES
    [body, ctype]
  rescue
    [nil, nil]
  end
end
