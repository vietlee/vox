class QrCodesController < ActionController::Base
  def scan
    qr = QrCode.find_by!(token: params[:token])
    qr.increment_scan!
    redirect_to qr.resource_url, allow_other_host: true
  end

  def image
    require "chunky_png"

    qr = QrCode.find_by!(token: params[:token])
    target_url = qr_scan_url(token: qr.token)
    qr_code = RQRCode::QRCode.new(target_url, level: :h)

    # ── Dimensions ────────────────────────────────────────────────────────────
    scale    = 12          # pixels per module (higher = sharper)
    pad      = 48          # padding around QR (px)
    text_h   = 56          # bottom area for "VOX" label
    radius   = 28          # corner radius for background rect (drawn manually)
    modules  = qr_code.modules.size
    qr_px    = modules * scale
    total_w  = qr_px + pad * 2
    total_h  = total_w + text_h

    # ── Colors ────────────────────────────────────────────────────────────────
    white      = ChunkyPNG::Color.rgba(255, 255, 255, 255)
    qr_color   = ChunkyPNG::Color.rgba( 67,  56, 202, 255)  # indigo-700 #4338ca
    border_col = ChunkyPNG::Color.rgba(224, 231, 255, 255)  # #e0e7ff
    brand_blue = ChunkyPNG::Color.rgba( 26, 107, 255, 255)  # #1A6BFF
    transparent = ChunkyPNG::Color::TRANSPARENT

    # ── Canvas ────────────────────────────────────────────────────────────────
    img = ChunkyPNG::Image.new(total_w, total_h, white)

    # Draw QR modules
    qr_code.modules.each_with_index do |row, ri|
      row.each_with_index do |mod, ci|
        next unless mod
        x0 = pad + ci * scale
        y0 = pad + ri * scale
        (x0...x0 + scale).each do |x|
          (y0...y0 + scale).each do |y|
            img[x, y] = qr_color
          end
        end
      end
    end

    # ── VOX logo in center ────────────────────────────────────────────────────
    # White background square behind logo
    logo_bg  = (total_w * 0.20).round.then { |n| n + (n % 2) }  # even
    logo_sz  = logo_bg - 12
    lx       = (total_w - logo_bg) / 2
    ly       = (total_h - text_h - logo_bg) / 2

    # Fill white square
    (lx...lx + logo_bg).each do |x|
      (ly...ly + logo_bg).each do |y|
        img[x, y] = white
      end
    end

    # Draw VOX icon scaled to logo_sz inside logo_bg (centered)
    icon_off_x = lx + (logo_bg - logo_sz) / 2
    icon_off_y = ly + (logo_bg - logo_sz) / 2
    s = logo_sz / 36.0  # scale factor (icon viewBox = 36×36)

    # Blue rounded square background of icon
    draw_filled_rect(img, icon_off_x, icon_off_y, logo_sz, logo_sz, brand_blue)

    # White rounded rect (speech bubble body): x=6,y=6,w=24,h=19,rx=5
    draw_filled_rect(img,
      icon_off_x + (6 * s).round, icon_off_y + (6 * s).round,
      (24 * s).round, (19 * s).round, white)

    # Three blue bars
    [
      [10, 11, 4, 7],
      [16,  8, 4, 13],
      [22, 10, 4,  9]
    ].each do |bx, by, bw, bh|
      draw_filled_rect(img,
        icon_off_x + (bx * s).round, icon_off_y + (by * s).round,
        (bw * s).round, (bh * s).round, brand_blue)
    end

    # Tail triangle: points 10,24  6,31  16,24
    draw_triangle(img,
      icon_off_x + (10 * s).round, icon_off_y + (24 * s).round,
      icon_off_x + ( 6 * s).round, icon_off_y + (31 * s).round,
      icon_off_x + (16 * s).round, icon_off_y + (24 * s).round,
      white)

    # ── Separator line ────────────────────────────────────────────────────────
    sep_y = total_h - text_h
    (pad...total_w - pad).each { |x| img[x, sep_y] = border_col }

    # ── "VOX" text — rasterised letter shapes ─────────────────────────────────
    draw_vox_text(img, total_w, sep_y + (text_h / 2) - 10, brand_blue)

    png_data = img.to_blob
    send_data png_data,
      type:        "image/png",
      disposition: "inline",
      filename:    "qrcode.png"
  end

  private

  # Fill a rectangle with color (no anti-alias needed for pixel art)
  def draw_filled_rect(img, x, y, w, h, color)
    x2 = [x + w, img.width].min
    y2 = [y + h, img.height].min
    ([x, 0].max...x2).each do |px|
      ([y, 0].max...y2).each do |py|
        img[px, py] = color
      end
    end
  end

  # Fill a triangle using scanline
  def draw_triangle(img, x0, y0, x1, y1, x2, y2, color)
    pts = [[x0, y0], [x1, y1], [x2, y2]].sort_by { |_, y| y }
    min_y = pts[0][1]; max_y = pts[2][1]
    (min_y..max_y).each do |y|
      xs = []
      [[pts[0], pts[1]], [pts[1], pts[2]], [pts[0], pts[2]]].each do |(ax, ay), (bx, by)|
        next if (by - ay).zero?
        next unless (ay..by).include?(y) || (by..ay).include?(y)
        t = (y - ay).to_f / (by - ay)
        xs << (ax + t * (bx - ax)).round
      end
      next if xs.size < 2
      xs.sort!
      (xs.first..xs.last).each do |x|
        img[x, y] = color if x >= 0 && x < img.width && y >= 0 && y < img.height
      end
    end
  end

  # Pixel-art "VOX" lettering centred at (cx, top_y)
  def draw_vox_text(img, total_w, top_y, color)
    # Each letter is a 5×7 pixel bitmap
    v_map = [
      [1,0,0,0,1],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [0,1,0,1,0],
      [0,1,0,1,0],
      [0,0,1,0,0]
    ]
    o_map = [
      [0,1,1,1,0],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [1,0,0,0,1],
      [0,1,1,1,0]
    ]
    x_map = [
      [1,0,0,0,1],
      [0,1,0,1,0],
      [0,1,0,1,0],
      [0,0,1,0,0],
      [0,1,0,1,0],
      [0,1,0,1,0],
      [1,0,0,0,1]
    ]

    px   = 4   # pixel size per dot
    gap  = 6   # gap between letters
    letters = [v_map, o_map, x_map]
    letter_w = 5 * px
    total_text_w = letters.size * letter_w + (letters.size - 1) * gap
    start_x = (total_w - total_text_w) / 2

    letters.each_with_index do |bitmap, li|
      lx = start_x + li * (letter_w + gap)
      bitmap.each_with_index do |row, ri|
        row.each_with_index do |dot, ci|
          next if dot.zero?
          x0 = lx + ci * px
          y0 = top_y + ri * px
          draw_filled_rect(img, x0, y0, px, px, color)
        end
      end
    end
  end
end
