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
      color:           "4338ca",
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
        <!-- White background -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="#ffffff"/>
        <!-- Border -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="none" stroke="#e0e7ff" stroke-width="2"/>

        <!-- QR modules -->
        <g transform="translate(#{pad}, #{pad})">#{inner_svg}</g>

        <!-- Logo white background -->
        <rect x="#{logo_x}" y="#{logo_y}" width="#{logo_bg}" height="#{logo_bg}" rx="#{(logo_bg * 0.22).round}" ry="#{(logo_bg * 0.22).round}" fill="#ffffff" stroke="#e0e7ff" stroke-width="1.5"/>

        <!-- Icon only (no VOX text) -->
        <g transform="translate(#{icon_x}, #{icon_y}) scale(#{(logo_sz / 36.0).round(4)})">
          <rect x="0" y="0" width="36" height="36" rx="9" fill="#1A6BFF"/>
          <polygon points="10,24 6,31 16,24" fill="white"/>
          <rect x="6" y="6" width="24" height="19" rx="5" fill="white"/>
          <rect x="10" y="11" width="4" height="7" rx="1" fill="#1A6BFF"/>
          <rect x="16" y="8" width="4" height="13" rx="1" fill="#1A6BFF"/>
          <rect x="23" y="10" width="4" height="9" rx="1" fill="#1A6BFF"/>
        </g>
      </svg>
    SVG
  end
end
