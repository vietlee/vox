class QrCodesController < ActionController::Base
  def scan
    qr = QrCode.find_by!(token: params[:token])
    qr.increment_scan!
    redirect_to qr.resource_url, allow_other_host: true
  end

  def image
    qr = QrCode.find_by!(token: params[:token])
    target_url = qr_scan_url(token: qr.token)
    # Use error correction level H (30%) — allows logo to cover ~20% of modules
    qr_code = RQRCode::QRCode.new(target_url, level: :h)

    mod_size = 6
    pad      = 24
    radius   = 16
    modules  = qr_code.modules.size
    qr_px    = modules * mod_size
    total    = qr_px + pad * 2

    # Generate raw QR path (no standalone wrapper)
    inner_svg = qr_code.as_svg(
      color:            "4338ca",   # indigo-700
      shape_rendering:  "crispEdges",
      module_size:      mod_size,
      standalone:       false,
      use_path:         true,
      offset:           0
    )

    # Logo dimensions — ~22% of total, centered
    logo_bg  = (total * 0.22).round
    logo_sz  = logo_bg - 8          # icon inside white circle
    logo_x   = (total - logo_bg) / 2
    logo_y   = (total - logo_bg) / 2
    icon_x   = (total - logo_sz) / 2
    icon_y   = (total - logo_sz) / 2

    svg = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{total} #{total}" width="#{total}" height="#{total}" shape-rendering="crispEdges">
        <defs>
          <clipPath id="qr-clip">
            <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}"/>
          </clipPath>
        </defs>

        <!-- White background -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="#ffffff"/>
        <!-- Subtle indigo border -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="none" stroke="#e0e7ff" stroke-width="2"/>

        <!-- QR modules -->
        <g transform="translate(#{pad}, #{pad})">
          #{inner_svg}
        </g>

        <!-- Logo: white rounded square background -->
        <rect x="#{logo_x}" y="#{logo_y}" width="#{logo_bg}" height="#{logo_bg}" rx="#{(logo_bg * 0.22).round}" ry="#{(logo_bg * 0.22).round}" fill="#ffffff" stroke="#e0e7ff" stroke-width="1.5"/>

        <!-- VOX icon (36×36 viewBox scaled to logo_sz) -->
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

    render plain: svg, content_type: "image/svg+xml"
  end
end
