class QrCodesController < ActionController::Base
  def scan
    qr = QrCode.find_by!(token: params[:token])
    qr.increment_scan!
    redirect_to qr.resource_url, allow_other_host: true
  end

  def image
    qr = QrCode.find_by!(token: params[:token])
    target_url = qr_scan_url(token: qr.token)
    qr_code = RQRCode::QRCode.new(target_url)

    # Generate raw QR SVG (no standalone wrapper — we wrap it ourselves)
    inner_svg = qr_code.as_svg(
      color: "4338ca",        # indigo-700
      shape_rendering: "crispEdges",
      module_size: 6,
      standalone: false,
      use_path: true,
      offset: 0
    )

    # Parse inner dimensions: RQRCode draws modules starting at (0,0)
    modules = qr_code.modules.size           # number of modules per side
    mod_size = 6
    qr_px = modules * mod_size               # raw QR size in px
    pad = 24                                 # padding on each side
    radius = 16                              # corner radius
    total = qr_px + pad * 2

    svg = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{total} #{total}" width="#{total}" height="#{total}" shape-rendering="crispEdges">
        <defs>
          <clipPath id="rounded-clip">
            <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}"/>
          </clipPath>
        </defs>
        <!-- White background with rounded corners -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="#ffffff"/>
        <!-- Subtle border -->
        <rect width="#{total}" height="#{total}" rx="#{radius}" ry="#{radius}" fill="none" stroke="#e0e7ff" stroke-width="2"/>
        <!-- QR modules shifted by padding -->
        <g transform="translate(#{pad}, #{pad})" clip-path="url(#rounded-clip)">
          #{inner_svg}
        </g>
      </svg>
    SVG

    render plain: svg, content_type: "image/svg+xml"
  end
end
