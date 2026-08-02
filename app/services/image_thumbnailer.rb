require "image_processing/vips"
require "tempfile"

# Downscales image bytes on the fly (via libvips) so tiny thumbnails don't
# ship the full-resolution image. Returns nil when `w` is absent/out of range
# or anything fails, so callers fall back to serving the original bytes.
module ImageThumbnailer
  module_function

  def resize(bytes, w)
    w = w.to_i
    return nil unless bytes.present? && w.between?(16, 512)

    tmp = Tempfile.new(["thumb", ".img"])
    tmp.binmode
    tmp.write(bytes)
    tmp.flush
    tmp.rewind
    ImageProcessing::Vips.source(tmp.path).resize_to_limit(w, w).call.read
  rescue => e
    Rails.logger.warn "[ImageThumbnailer] #{e.message}"
    nil
  ensure
    tmp&.close!
  end
end
