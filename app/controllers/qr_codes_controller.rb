class QrCodesController < ActionController::Base
  def scan
    qr = QrCode.find_by!(token: params[:token])
    qr.increment_scan!
    redirect_to qr.resource_url, allow_other_host: true
  end

  def image
    require "open3"
    require "tempfile"

    qr = QrCode.find_by!(token: params[:token])
    target_url = qr_scan_url(token: qr.token)
    qr_code    = RQRCode::QRCode.new(target_url, level: :h)

    svg = build_qr_svg(qr_code)

    # Use rsvg-convert (available via ImageMagick delegate) for crisp PNG
    png_data = nil
    Tempfile.create(["qr", ".svg"]) do |f|
      f.write(svg)
      f.flush
      png_data, _err, _st = Open3.capture3("rsvg-convert", "--dpi-x=144", "--dpi-y=144", f.path)
    end

    send_data png_data,
      type:        "image/png",
      disposition: "inline",
      filename:    "qrcode.png"
  end

  private

  def build_qr_svg(qr_code)
    mod_size   = 6
    pad        = 24
    radius     = 16
    modules    = qr_code.modules.size
    qr_px      = modules * mod_size
    total      = qr_px + pad * 2

    inner_svg = qr_code.as_svg(
      color:           "1e3a5f",
      shape_rendering: "crispEdges",
      module_size:     mod_size,
      standalone:      false,
      use_path:        true,
      offset:          0
    )

    logo_bg = (total * 0.22).round
    logo_sz = logo_bg - 8
    logo_x  = (total - logo_bg) / 2
    logo_y  = (total - logo_bg) / 2
    icon_x  = (total - logo_sz) / 2
    icon_y  = (total - logo_sz) / 2

    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{total} #{total}" width="#{total}" height="#{total}" shape-rendering="crispEdges">
        <defs>
          <linearGradient id="voxbg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stop-color="#6C5CE7"/>
            <stop offset="1" stop-color="#2D1B8B"/>
          </linearGradient>
        </defs>

        <!-- White background -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="#ffffff"/>
        <!-- Border -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="none" stroke="#e0e7ff" stroke-width="2"/>

        <!-- QR modules -->
        <g transform="translate(#{pad}, #{pad})">#{inner_svg}</g>

        <!-- Logo white background -->
        <rect x="#{logo_x}" y="#{logo_y}" width="#{logo_bg}" height="#{logo_bg}" rx="#{(logo_bg * 0.22).round}" ry="#{(logo_bg * 0.22).round}" fill="#ffffff" stroke="#e0e7ff" stroke-width="1.5"/>

        <!-- VOX logo: soundwave mark (100×100 viewBox scaled to logo_sz) -->
        <g transform="translate(#{icon_x}, #{icon_y}) scale(#{(logo_sz / 100.0).round(4)})">
          <rect x="4" y="4" width="92" height="92" rx="24" fill="url(#voxbg)"/>
          <rect x="46" y="27" width="8" height="46" rx="4" fill="#ffffff"/>
          <rect x="32" y="34" width="8" height="32" rx="4" fill="#ffffff" opacity="0.92"/>
          <rect x="60" y="34" width="8" height="32" rx="4" fill="#ffffff" opacity="0.92"/>
          <rect x="18" y="41" width="8" height="18" rx="4" fill="#ffffff" opacity="0.78"/>
          <rect x="74" y="41" width="8" height="18" rx="4" fill="#ffffff" opacity="0.78"/>
        </g>
      </svg>
    SVG
  end
end
