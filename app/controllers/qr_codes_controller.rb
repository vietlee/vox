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
    svg = qr_code.as_svg(
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true,
      use_path: true
    )
    render plain: svg, content_type: "image/svg+xml"
  end
end
