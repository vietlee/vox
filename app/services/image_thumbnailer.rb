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
    # Force webp output — vips can't infer the format from the ".img" temp name,
    # and webp is compact + supported by Flutter/browsers. Callers serve it as
    # image/webp. Returns [bytes, "image/webp"].
    out = ImageProcessing::Vips.source(tmp.path).resize_to_limit(w, w).convert("webp").saver(quality: 78).call.read
    [out, "image/webp"]
  rescue => e
    Rails.logger.warn "[ImageThumbnailer] #{e.message}"
    nil
  ensure
    tmp&.close!
  end
end
