class ContentOutlineGenerator
  PPTX_SCRIPT        = Rails.root.join("scripts", "generate_pptx.py").to_s
  RENDER_SLIDES_JS   = Rails.root.join("scripts", "render_slides.js").to_s
  PNGS_TO_PPTX_PY    = Rails.root.join("scripts", "pngs_to_pptx.py").to_s

  SW = 10.0; SH = 5.625; LM = 0.60; CW = 8.80

  # card_style: visual treatment of card/rect elements (flat/shadow/outlined/glass/bold)
  # cover_style: cover+summary layout (left/centered/minimal)
  # deco_style: cover decoration pattern (circles/wave/dots/diagonal/none)
  DECK_THEMES = {
    # ── Gradient cover backgrounds ──────────────────────────────────────────
    "green"     => { "cover_bg" => "linear-gradient(135deg,#064E3B 0%,#065F46 55%,#047857 100%)",
                     "primary" => "#10B981", "primary_dk" => "#065F46",
                     "primary_lt" => "#6EE7B7", "primary_xl" => "#D1FAE5",
                     "accent" => "#34D399", "card_bgs" => %w[#E8F5F0 #D1F5E0 #C8F5D4],
                     "card_icons" => %w[#10B981 #047857 #065F46], "text_light" => "#A7F3D0",
                     "cover_style" => "left", "card_style" => "flat", "deco_style" => "circles" },
    "blue"      => { "cover_bg" => "linear-gradient(135deg,#1e3a5f 0%,#1D4ED8 60%,#2563EB 100%)",
                     "primary" => "#2563EB", "primary_dk" => "#1E40AF",
                     "primary_lt" => "#93C5FD", "primary_xl" => "#DBEAFE",
                     "accent" => "#60A5FA", "card_bgs" => %w[#EFF6FF #DBEAFE #E0EDFF],
                     "card_icons" => %w[#3B82F6 #2563EB #1D4ED8], "text_light" => "#BFDBFE",
                     "cover_style" => "left", "card_style" => "shadow", "deco_style" => "split" },
    "purple"    => { "cover_bg" => "linear-gradient(135deg,#1E0B3A 0%,#3B0764 50%,#6B21A8 100%)",
                     "primary" => "#9333EA", "primary_dk" => "#7E22CE",
                     "primary_lt" => "#C4B5FD", "primary_xl" => "#EDE9FE",
                     "accent" => "#C084FC", "card_bgs" => %w[#F5F3FF #EDE9FE #E9D5FF],
                     "card_icons" => %w[#9333EA #7E22CE #6B21A8], "text_light" => "#DDD6FE",
                     "cover_style" => "centered", "card_style" => "glass", "deco_style" => "circles" },
    "red"       => { "cover_bg" => "linear-gradient(135deg,#450A0A 0%,#7F1D1D 50%,#B91C1C 100%)",
                     "primary" => "#EF4444", "primary_dk" => "#DC2626",
                     "primary_lt" => "#FCA5A5", "primary_xl" => "#FEE2E2",
                     "accent" => "#FB923C", "card_bgs" => %w[#FFF7ED #FEE2E2 #FFE4D6],
                     "card_icons" => %w[#EF4444 #DC2626 #B91C1C], "text_light" => "#FECACA",
                     "cover_style" => "left", "card_style" => "bold", "deco_style" => "diagonal" },
    "teal"      => { "cover_bg" => "linear-gradient(135deg,#042F2E 0%,#134E4A 55%,#0F766E 100%)",
                     "primary" => "#0D9488", "primary_dk" => "#0F766E",
                     "primary_lt" => "#5EEAD4", "primary_xl" => "#CCFBF1",
                     "accent" => "#2DD4BF", "card_bgs" => %w[#F0FDFA #CCFBF1 #C7F5EE],
                     "card_icons" => %w[#0D9488 #0F766E #115E59], "text_light" => "#99F6E4",
                     "cover_style" => "minimal", "card_style" => "outlined", "deco_style" => "corner" },
    "amber"     => { "cover_bg" => "linear-gradient(135deg,#431407 0%,#78350F 55%,#92400E 100%)",
                     "primary" => "#F59E0B", "primary_dk" => "#D97706",
                     "primary_lt" => "#FCD34D", "primary_xl" => "#FEF3C7",
                     "accent" => "#FBBF24", "card_bgs" => %w[#FFFBEB #FEF3C7 #FDE68A],
                     "card_icons" => %w[#F59E0B #D97706 #B45309], "text_light" => "#FDE68A",
                     "cover_style" => "centered", "card_style" => "flat", "deco_style" => "wave" },
    "slate"     => { "cover_bg" => "linear-gradient(135deg,#020617 0%,#0F172A 60%,#1E293B 100%)",
                     "primary" => "#64748B", "primary_dk" => "#475569",
                     "primary_lt" => "#CBD5E1", "primary_xl" => "#F1F5F9",
                     "accent" => "#818CF8", "card_bgs" => %w[#F8FAFC #F1F5F9 #E9EEF4],
                     "card_icons" => %w[#6366F1 #4F46E5 #4338CA], "text_light" => "#E2E8F0",
                     "cover_style" => "minimal", "card_style" => "shadow", "deco_style" => "dots" },
    "earth"     => { "cover_bg" => "linear-gradient(135deg,#1C0A00 0%,#3B1F0A 55%,#6B3B1F 100%)",
                     "primary" => "#92400E", "primary_dk" => "#78350F",
                     "primary_lt" => "#D97706", "primary_xl" => "#FEF3C7",
                     "accent" => "#D97706", "card_bgs" => %w[#FDF6EE #FEF3C7 #FEE0B6],
                     "card_icons" => %w[#92400E #78350F #6B3B1F], "text_light" => "#FDE68A",
                     "cover_style" => "left", "card_style" => "bold", "deco_style" => "geo" },
    "coral"     => { "cover_bg" => "linear-gradient(135deg,#450614 0%,#881337 55%,#BE123C 100%)",
                     "primary" => "#F43F5E", "primary_dk" => "#E11D48",
                     "primary_lt" => "#FDA4AF", "primary_xl" => "#FFE4E6",
                     "accent" => "#FB7185", "card_bgs" => %w[#FFF1F2 #FFE4E6 #FECDD3],
                     "card_icons" => %w[#F43F5E #E11D48 #BE123C], "text_light" => "#FCA5AF",
                     "cover_style" => "centered", "card_style" => "glass", "deco_style" => "split" },
    "ocean"     => { "cover_bg" => "linear-gradient(135deg,#021C2C 0%,#0C4A6E 55%,#075985 100%)",
                     "primary" => "#0369A1", "primary_dk" => "#075985",
                     "primary_lt" => "#7DD3FC", "primary_xl" => "#E0F2FE",
                     "accent" => "#38BDF8", "card_bgs" => %w[#F0F9FF #E0F2FE #BAE6FD],
                     "card_icons" => %w[#0369A1 #075985 #0C4A6E], "text_light" => "#BAE6FD",
                     "cover_style" => "left", "card_style" => "shadow", "deco_style" => "corner" },
    "berry"     => { "cover_bg" => "linear-gradient(135deg,#2D0416 0%,#500724 55%,#831843 100%)",
                     "primary" => "#DB2777", "primary_dk" => "#BE185D",
                     "primary_lt" => "#F9A8D4", "primary_xl" => "#FCE7F3",
                     "accent" => "#F472B6", "card_bgs" => %w[#FDF2F8 #FCE7F3 #FBCFE8],
                     "card_icons" => %w[#DB2777 #BE185D #9D174D], "text_light" => "#F9A8D4",
                     "cover_style" => "centered", "card_style" => "glass", "deco_style" => "dots" },
    "midnight"  => { "cover_bg" => "linear-gradient(135deg,#020617 0%,#0F0B2D 55%,#1E0B5C 100%)",
                     "primary" => "#4F46E5", "primary_dk" => "#3730A3",
                     "primary_lt" => "#A5B4FC", "primary_xl" => "#E0E7FF",
                     "accent" => "#818CF8", "card_bgs" => %w[#EEF2FF #E0E7FF #D4DBFF],
                     "card_icons" => %w[#4F46E5 #3730A3 #312E81], "text_light" => "#C7D2FE",
                     "cover_style" => "minimal", "card_style" => "outlined", "deco_style" => "geo" },
    # ── 8 new themes ────────────────────────────────────────────────────────
    "rose"      => { "cover_bg" => "linear-gradient(135deg,#4C0519 0%,#9F1239 50%,#E11D48 100%)",
                     "primary" => "#F43F5E", "primary_dk" => "#BE123C",
                     "primary_lt" => "#FDA4AF", "primary_xl" => "#FFE4E6",
                     "accent" => "#FB923C", "card_bgs" => %w[#FFF1F2 #FFE4E6 #FEF2F2],
                     "card_icons" => %w[#F43F5E #E11D48 #FB923C], "text_light" => "#FECDD3",
                     "cover_style" => "centered", "card_style" => "bold", "deco_style" => "diagonal" },
    "forest"    => { "cover_bg" => "linear-gradient(160deg,#052E16 0%,#14532D 55%,#166534 100%)",
                     "primary" => "#16A34A", "primary_dk" => "#15803D",
                     "primary_lt" => "#86EFAC", "primary_xl" => "#DCFCE7",
                     "accent" => "#4ADE80", "card_bgs" => %w[#F0FDF4 #DCFCE7 #D1FAE5],
                     "card_icons" => %w[#16A34A #15803D #166534], "text_light" => "#BBF7D0",
                     "cover_style" => "left", "card_style" => "shadow", "deco_style" => "split" },
    "gold"      => { "cover_bg" => "linear-gradient(135deg,#1A0F00 0%,#451A03 50%,#92400E 100%)",
                     "primary" => "#D97706", "primary_dk" => "#B45309",
                     "primary_lt" => "#FDE68A", "primary_xl" => "#FEF9C3",
                     "accent" => "#FCD34D", "card_bgs" => %w[#FFFBEB #FEF9C3 #FEF3C7],
                     "card_icons" => %w[#D97706 #B45309 #92400E], "text_light" => "#FDE68A",
                     "cover_style" => "left", "card_style" => "bold", "deco_style" => "corner" },
    "ice"       => { "cover_bg" => "linear-gradient(160deg,#0C4A6E 0%,#0369A1 45%,#38BDF8 100%)",
                     "primary" => "#0EA5E9", "primary_dk" => "#0284C7",
                     "primary_lt" => "#BAE6FD", "primary_xl" => "#F0F9FF",
                     "accent" => "#7DD3FC", "card_bgs" => %w[#F0F9FF #E0F2FE #CFFAFE],
                     "card_icons" => %w[#0EA5E9 #0284C7 #0369A1], "text_light" => "#E0F2FE",
                     "cover_style" => "minimal", "card_style" => "glass", "deco_style" => "wave" },
    "charcoal"  => { "cover_bg" => "linear-gradient(135deg,#111827 0%,#1F2937 60%,#374151 100%)",
                     "primary" => "#6B7280", "primary_dk" => "#4B5563",
                     "primary_lt" => "#D1D5DB", "primary_xl" => "#F3F4F6",
                     "accent" => "#F59E0B", "card_bgs" => %w[#F9FAFB #F3F4F6 #E5E7EB],
                     "card_icons" => %w[#F59E0B #D97706 #B45309], "text_light" => "#E5E7EB",
                     "cover_style" => "left", "card_style" => "bold", "deco_style" => "dots" },
    "lavender"  => { "cover_bg" => "linear-gradient(135deg,#2E1065 0%,#4C1D95 55%,#7C3AED 100%)",
                     "primary" => "#7C3AED", "primary_dk" => "#6D28D9",
                     "primary_lt" => "#C4B5FD", "primary_xl" => "#EDE9FE",
                     "accent" => "#A78BFA", "card_bgs" => %w[#F5F3FF #EDE9FE #DDD6FE],
                     "card_icons" => %w[#7C3AED #6D28D9 #5B21B6], "text_light" => "#DDD6FE",
                     "cover_style" => "centered", "card_style" => "glass", "deco_style" => "geo" },
    "sunset"    => { "cover_bg" => "linear-gradient(135deg,#7C2D12 0%,#C2410C 40%,#BE185D 100%)",
                     "primary" => "#EA580C", "primary_dk" => "#C2410C",
                     "primary_lt" => "#FED7AA", "primary_xl" => "#FFF7ED",
                     "accent" => "#FB923C", "card_bgs" => %w[#FFF7ED #FEE2E2 #FFE4D6],
                     "card_icons" => %w[#EA580C #C2410C #BE185D], "text_light" => "#FED7AA",
                     "cover_style" => "centered", "card_style" => "bold", "deco_style" => "split" },
    "jade"      => { "cover_bg" => "linear-gradient(135deg,#022C22 0%,#064E3B 55%,#065F46 100%)",
                     "primary" => "#059669", "primary_dk" => "#047857",
                     "primary_lt" => "#6EE7B7", "primary_xl" => "#ECFDF5",
                     "accent" => "#34D399", "card_bgs" => %w[#ECFDF5 #D1FAE5 #A7F3D0],
                     "card_icons" => %w[#059669 #047857 #065F46], "text_light" => "#A7F3D0",
                     "cover_style" => "minimal", "card_style" => "outlined", "deco_style" => "none" },
    # ── Original: clean white, no gradients ─────────────────────────────────
    "original"  => { "cover_bg" => "linear-gradient(135deg,#0A1929 0%,#0F2942 55%,#1a3a5c 100%)",
                     "primary" => "#0F2942", "primary_dk" => "#0A1929",
                     "primary_lt" => "#4A7FA5", "primary_xl" => "#EEF4F9",
                     "accent" => "#D4A24C", "card_bgs" => %w[#D8E8F2 #C4D9E9 #B0CAE0],
                     "card_icons" => %w[#0F2942 #1B3F62 #2A5A87], "text_light" => "#B8C7D6",
                     "fg" => "#FFFFFF", "fg_light" => "rgba(255,255,255,0.72)",
                     "cover_style" => "clean", "card_style" => "outlined", "deco_style" => "clean" },
  }.freeze

  def self.call(outline)   = new(outline).call
  def self.ai_edit(outline, edit_prompt) = new(outline).ai_edit(edit_prompt)

  COLOR_NAME_MAP = {
    "đỏ" => "#DC2626", "red" => "#DC2626",
    "xanh dương" => "#2563EB", "xanh" => "#2563EB", "blue" => "#2563EB", "navy" => "#1E3A8A",
    "xanh lá" => "#16A34A", "green" => "#16A34A",
    "vàng" => "#D97706", "yellow" => "#CA8A04", "gold" => "#D97706",
    "cam" => "#EA580C", "orange" => "#EA580C",
    "tím" => "#7C3AED", "purple" => "#7C3AED",
    "hồng" => "#DB2777", "pink" => "#DB2777",
    "nâu" => "#92400E",
    "ngọc" => "#0D9488", "teal" => "#0D9488",
    "xám" => "#6B7280",
    "đen" => "#111827", "black" => "#111827",
    "trắng" => "#F1F5F9", "white" => "#F1F5F9"
  }.freeze

  def initialize(outline)
    @outline = outline
    @user_color = detect_user_color
  end

  # Extract hex color from user's prompt_input. Returns nil if no color mentioned.
  def detect_user_color
    prompt = [@outline.prompt_input.to_s, @outline.title.to_s].join(" ")
    return nil if prompt.strip.empty?

    # Direct hex color
    if (hex = prompt.match(/#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/))
      raw = hex[0]
      return raw.length == 4 ? "##{raw[1]*2}#{raw[2]*2}#{raw[3]*2}" : raw
    end

    # Color name
    prompt_down = prompt.downcase
    COLOR_NAME_MAP.each do |name, hex|
      return hex if prompt_down.include?(name)
    end

    nil
  end

  def recompile(raw_slides, theme_name)
    build_deck_schema(raw_slides, theme_name)
  end

  def recompile_and_export(raw_slides, theme_name)
    deck = build_deck_schema(raw_slides, theme_name)
    pptx_path = generate_pptx(deck)
    attach_pptx(pptx_path) if pptx_path
    deck
  end

  def call
    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    if @outline.output_type == "slide"
      result = svc.call(system_prompt: slide_system, user_prompt: slide_user, max_tokens: 8000)
      Rails.logger.info "[SlideGen] AI result length=#{result.to_s.length} slide_count=#{result.to_s.scan(/---SLIDE---/).length} end_count=#{result.to_s.scan(/---END---/).length}"
      Rails.logger.info "[SlideGen] Last 200 chars: #{result.to_s[-200..]}"
      raw_slides = parse_slides(result)
      Rails.logger.info "[SlideGen] Parsed #{raw_slides.length} slides, color=#{@slide_color}"
      deck = build_deck_schema(raw_slides, @slide_theme || "original")
      html = slides_to_html(deck)
      pptx_path = generate_pptx(deck)
      @outline.update!(content: html, slide_json: deck.to_json, status: :done)
      attach_pptx(pptx_path) if pptx_path
    else
      result = svc.call(system_prompt: generic_system, user_prompt: generic_user, max_tokens: 3000)
      @outline.update!(content: markdown_to_html(result), status: :done)
    end

    cost = @outline.output_type == "slide" ? 5 : 2
    @outline.workspace.credit_subscription&.deduct_credits!(cost)
  end

  def ai_edit(edit_prompt)
    current_deck = JSON.parse(@outline.slide_json || "{}")
    raw_slides = current_deck["slides"]&.map { |s| s["raw"] || s } || []
    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    uploaded_images = []  # [{ index:, url:, content_type:, filename: }]
    image_paths = []

    if @outline.edit_images.attached?
      Dir.mktmpdir do |dir|
        @outline.edit_images.each_with_index do |img, i|
          path = File.join(dir, img.filename.to_s)
          File.open(path, "wb") { |f| img.download { |chunk| f.write(chunk) } }
          image_paths << path
          ct = img.content_type.presence || "image/png"
          b64 = Base64.strict_encode64(File.binread(path))
          data_url = "data:#{ct};base64,#{b64}"
          uploaded_images << { index: i + 1, url: data_url, content_type: ct, filename: img.filename.to_s }
        end
        _do_ai_edit(svc, raw_slides, edit_prompt, uploaded_images, image_paths, current_deck)
        return
      end
    end

    _do_ai_edit(svc, raw_slides, edit_prompt, uploaded_images, image_paths, current_deck)
  end

  def _do_ai_edit(svc, raw_slides, edit_prompt, uploaded_images, image_paths, current_deck)
    existing_theme = current_deck.dig("theme", "name") || "original"

    # Build compact element map for AI - all types with relevant editable fields
    el_map = {}
    (current_deck["slides"] || []).each_with_index do |slide, si|
      entries = []
      (slide["elements"] || []).each do |el|
        type = el["type"].to_s
        base = { "id" => el["id"], "type" => type, "x" => el["x"], "y" => el["y"], "w" => el["w"], "h" => el["h"] }
        entry = case type
        when "text"
          next unless el["content"].to_s.strip.present?
          base.merge("role" => el["id"].to_s.split("_").first, "content" => el["content"])
        when "image"
          base.merge("filename" => el["filename"].to_s)
        when "icon"
          base.merge("name" => el["name"].to_s, "color" => el.dig("style", "color"))
        when /\Achart/
          # Include chart labels/data so AI can edit chart content
          base.merge("chartType" => type, "labels" => el["labels"], "datasets" => el["datasets"])
        when "rect", "ellipse", "line", "triangle", "circle"
          base.merge("color" => el.dig("style", "fill") || el.dig("style", "stroke"))
        else
          next  # skip unknown/video types
        end
        entries << entry
      end
      el_map[si] = { "title" => slide["title"], "elements" => entries } if entries.any?
    end

    prompt = <<~PROMPT
      Bạn nhận được tất cả element của một bộ slide (#{el_map.size} slides).
      Slide có kích thước 10×5.625 inch. Tọa độ x, y và kích thước w, h đều tính bằng inch.
      Hãy thực hiện yêu cầu chỉnh sửa và trả về JSON chứa CÁC THAY ĐỔI.

      CÁC ELEMENT HIỆN TẠI:
      #{el_map.to_json}

      YÊU CẦU CHỈNH SỬA:
      #{edit_prompt}

      QUY TẮC:
      1. Trả về JSON duy nhất, không giải thích, không markdown.
      2. Format: {"changes": [{"id": "...", <các field thay đổi>}, ...]}
      3. Chỉ đưa vào "changes" những element CÓ thay đổi. Element không đổi → không đưa vào.
      4. Theo type:
         - text: có thể đổi "content"
         - image/icon/shape: có thể đổi "x", "y", "w", "h" — giữ tỉ lệ w/h gốc khi scale
         - icon: có thể đổi "name" (tên icon), "color"
         - chart: có thể đổi "labels", "datasets"
         - rect/ellipse/line/triangle: có thể đổi "color", "x", "y", "w", "h"
      5. Đảm bảo mọi element nằm trong slide: x ≥ 0, y ≥ 0, x+w ≤ 10, y+h ≤ 5.625.
      6. Không thêm/xóa element. Không đổi "type" của element.
    PROMPT

    result = svc.call(system_prompt: slide_edit_system, user_prompt: prompt, max_tokens: 4000)

    # Parse changes
    json_str = result.to_s.strip.gsub(/\A```(?:json)?\s*/i, '').gsub(/\s*```\z/, '').strip
    parsed   = JSON.parse(json_str)
    changes  = (parsed["changes"] || []).index_by { |c| c["id"] }

    Rails.logger.info "[AiEdit] Applying #{changes.size} element changes"

    # Apply changes directly to current_deck (deep clone first)
    deck = JSON.parse(current_deck.to_json)
    (deck["slides"] || []).each do |slide|
      (slide["elements"] || []).each do |el|
        ch = changes[el["id"]]
        next unless ch
        type = el["type"].to_s
        # Geometry fields — applicable to any type
        %w[x y w h].each { |f| el[f] = ch[f].to_f if ch[f] }
        case type
        when "text"
          el["content"] = ch["content"] if ch["content"]
        when "icon"
          el["name"] = ch["name"] if ch["name"]
          el["style"] ||= {}
          el["style"]["color"] = ch["color"] if ch["color"]
        when /\Achart/
          el["labels"]   = ch["labels"]   if ch["labels"]
          el["datasets"] = ch["datasets"] if ch["datasets"]
        when "rect", "ellipse", "line", "triangle", "circle"
          if ch["color"]
            el["style"] ||= {}
            el["style"]["fill"]   = ch["color"] if el.dig("style", "fill")
            el["style"]["stroke"] = ch["color"] if el.dig("style", "stroke")
          end
        end
      end
    end

    inject_images_into_deck(deck, uploaded_images, edit_prompt) if uploaded_images.any?

    html = slides_to_html(deck)
    pptx_path = generate_pptx(deck, image_paths: image_paths)
    @outline.update!(content: html, slide_json: deck.to_json, status: :done)
    attach_pptx(pptx_path) if pptx_path
  rescue JSON::ParserError => e
    Rails.logger.error "[AiEdit] JSON parse failed: #{e.message} | result: #{result.to_s[0..200]}"
    @outline.update!(status: :failed)
  rescue => e
    Rails.logger.error "[AiEdit] #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    @outline.update!(status: :failed)
  end

  # Inject uploaded images into slides based on IMAGE_REF markers or prompt keywords
  def inject_images_into_deck(deck, uploaded_images, edit_prompt)
    prompt_down = edit_prompt.downcase
    all_slides = prompt_down.include?("tất cả") || prompt_down.include?("mỗi") || prompt_down.include?("all") || prompt_down.include?("every")
    is_logo    = prompt_down.include?("logo")

    # Remove ALL previously injected images (top-right corner area, z=20) before re-injecting
    deck["slides"].each do |slide|
      slide["elements"]&.reject! do |el|
        el["type"] == "image" && el["z"].to_i == 20 && el["y"].to_f < 0.5
      end
    end

    uploaded_images.each do |im|
      # Measure actual image dimensions from base64 data to preserve aspect ratio
      img_w, img_h = measure_image_size(im)

      if is_logo
        # Logo top-right: max 2.4 x 0.85 inch, contain (no crop), preserve aspect ratio
        max_w = 2.4; max_h = 0.85
        scale = [max_w / img_w, max_h / img_h].min
        w = (img_w * scale).round(3); h = (img_h * scale).round(3)
        x = (SW - LM - w).round(3); y = 0.12
        obj_fit = "contain"
      else
        # Generic image: max 3.0 x 2.0 inch, cover
        max_w = 3.0; max_h = 2.0
        scale = [max_w / img_w, max_h / img_h].min
        w = (img_w * scale).round(3); h = (img_h * scale).round(3)
        x = (SW - LM - w).round(3); y = 0.15
        obj_fit = "contain"
      end

      # Reuse same ID across slides so re-runs replace instead of stack
      base_uid = "injected_img_#{im[:index]}"

      deck["slides"].each_with_index do |slide, si|
        has_ref = (slide["elements"] || []).any? do |el|
          el["type"] == "text" && el["content"].to_s.include?("image_#{im[:index]}")
        end
        next unless all_slides || has_ref || si == 0

        slide["elements"] ||= []

        # Remove any text placeholders AND any previously injected image with same base_uid
        slide["elements"].reject! do |el|
          (el["type"] == "text" && el["content"].to_s.match?(/image_#{im[:index]}/i)) ||
          (el["type"] == "image" && el["id"].to_s.start_with?(base_uid))
        end

        slide["elements"] << {
          "id" => "#{base_uid}_#{si}", "type" => "image",
          "src" => im[:url],
          "x" => x, "y" => y, "w" => w, "h" => h,
          "z" => 20, "objectFit" => obj_fit
        }
      end
    end
  end

  # Decode base64 image to measure its pixel dimensions, return [w_inch, h_inch]
  def measure_image_size(im)
    begin
      require 'base64'
      data = im[:url].split(',', 2).last
      raw  = Base64.decode64(data).b  # force ASCII-8BIT for binary comparison
      ct   = im[:content_type].to_s

      png_sig = "\x89PNG\r\n\x1a\n".b
      if ct.include?('png') && raw[0, 8] == png_sig
        px_w = raw[16, 4].unpack1('N')
        px_h = raw[20, 4].unpack1('N')
      elsif ct.include?('jpeg') || ct.include?('jpg')
        pos = 2
        while pos < raw.length
          marker = raw[pos, 2]&.unpack('n')&.first
          break unless marker
          pos += 2
          if marker >= 0xFFC0 && marker <= 0xFFCF && marker != 0xFFC4 && marker != 0xFFC8
            px_h = raw[pos + 3, 2]&.unpack1('n') || 0
            px_w = raw[pos + 5, 2]&.unpack1('n') || 0
            break
          end
          len = raw[pos, 2]&.unpack1('n') || 2
          pos += len
        end
      end

      px_w = px_w.to_i; px_h = px_h.to_i
      return [2.0, 1.0] if px_w == 0 || px_h == 0

      # Convert pixels to inches at 96dpi, cap at reasonable slide dimensions
      w_in = (px_w / 96.0).round(3)
      h_in = (px_h / 96.0).round(3)
      [w_in, h_in]
    rescue
      [2.0, 1.0]
    end
  end

  def slide_edit_system
    <<~SYS.squish
      Bạn là trợ lý chỉnh sửa slide thuyết trình chuyên nghiệp.
      Input: deck JSON. Output: deck JSON đã sửa — chỉ JSON thuần túy, không giải thích, không markdown.

      NGUYÊN TẮC:
      - Chỉ sửa đúng những gì được yêu cầu. Không đụng đến bất cứ thứ gì khác.
      - Giữ nguyên toàn bộ cấu trúc JSON, id, type, x, y, w, h, z của mọi element.
      - Khi sửa text: chỉ thay field "content". Không đổi font, size, color, position.
      - Không thêm/xóa slide hay element trừ khi được yêu cầu rõ ràng.
      - Output phải là JSON parse được ngay, không có gì khác.
    SYS
  end

  def slide_system
    <<~SYS.squish
      Bạn là chuyên gia thiết kế slide thuyết trình doanh nghiệp cấp cao (McKinsey, BCG, Bain).
      Trả lời bằng tiếng Việt. Chỉ xuất đúng format được chỉ định, không thêm gì khác.

      TRIẾT LÝ THIẾT KẾ (học từ các deck chuyên nghiệp):
      - "Sandwich": cover + closing dùng nền tối gradient, các slide content dùng nền trắng/sáng.
      - Mỗi slide chỉ truyền tải 1 thông điệp chính — không nhồi nhét.
      - Typography 3 cấp rõ ràng: Hero (tiêu đề to) / Heading (nhãn section) / Body (nội dung).
      - Mỗi slide content PHẢI có visual element: số liệu lớn, chart, grid card, hay timeline.
      - Tuyệt đối KHÔNG dùng plain bullet list thuần túy — luôn có cấu trúc visual.

      QUY TẮC BẮT BUỘC:
      1. COVER: TITLE = tên chủ đề ngắn (tối đa 4 từ). SUBTITLE = 1 câu mô tả định vị. KHÔNG có số liệu.
      2. Mỗi content slide có STYLE: category= (nhãn 2-3 từ viết hoa, ví dụ: "BỐI CẢNH THỊ TRƯỜNG").
      3. TITLE content slide: insight 1 câu (≤50 ký tự), viết thường, không dấu chấm hỏi.
      4. Layout đa dạng, KHÔNG lặp liên tiếp cùng layout — xen kẽ: stats, pillars, two-col, timeline, chart, donut.
      5. KHÔNG dùng emoji hay [icon placeholder]. KHÔNG có accent lines dưới title.
      6. TIÊU ĐỀ item/bullet: ≤25 ký tự. Giải thích sau "::".
      7. Mỗi slide lấp ≥85% diện tích — không để khoảng trắng lớn.
      8. NOTE bắt buộc: 2-3 câu gợi ý người thuyết trình (điểm nhấn, số liệu bổ sung, câu hỏi gợi mở).
      9. Số slide: 7–10 (1 cover + N content + 1 closing). Chất lượng hơn số lượng.
      10. FOOTER: chỉ dùng cho nguồn dữ liệu ("Nguồn: Nielsen Vietnam 2024") hoặc context thêm.
    SYS
  end

  def slide_user
    color_instruction = if @user_color
      "Màu chủ đạo đã được chỉ định bởi người dùng: #{@user_color} — dùng màu này.\nDòng đầu tiên trước ---SLIDE--- bắt buộc:\nCOLOR: #{@user_color}\n"
    else
      ""   # No color instruction — keep original theme's default gold #D4A24C
    end

    doc_section = if @outline.source_document_text.present?
      <<~DOC
        ---TÀI LIỆU THAM KHẢO---
        Người dùng đã cung cấp tài liệu sau. Hãy đọc kỹ và ưu tiên dùng dữ liệu, số liệu, ví dụ thực tế từ tài liệu này để làm phong phú nội dung slide:

        #{@outline.source_document_text.strip[0, 12_000]}

        ---HẾT TÀI LIỆU---
      DOC
    else
      ""
    end

    <<~PROMPT
      Tạo bộ slide thuyết trình CHUYÊN NGHIỆP, TRỰC QUAN, PHONG PHÚ cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      #{doc_section}
      #{color_instruction}

      Tạo số slide PHÙ HỢP (6–12 slide, tuỳ nội dung — 1 cover + N content + 1 summary), mỗi slide theo đúng format này:

      ---SLIDE---
      TITLE: Tiêu đề slide (viết thường tự nhiên, tối đa 50 ký tự, slide cover chỉ ghi TÊN dự án)
      SUBTITLE: Dòng mô tả ngắn bổ sung cho title (italic, 1 câu giải thích ngữ cảnh)
      LAYOUT: [tên layout]
      BODY:
      [nội dung theo format của layout đã chọn]
      STYLE: [tùy chọn style, xem bên dưới]
      FOOTER: [nguồn dữ liệu nhỏ — VD: "Nguồn: IMARC Group 2023"]
      NOTE: [SỐ LIỆU NỔI BẬT — hiển thị dạng dark banner. VD: "58,85 triệu USD → 175,41 triệu USD   Quy mô thị trường thuần chay Việt Nam, 2024 → 2033 (CAGR 11,54%)". Chỉ dùng cho slide có data đáng highlight]
      ---END---

      ═══════════════════════════════════════════
      CÁC LOẠI LAYOUT — chọn layout PHÙ HỢP NHẤT với nội dung:
      ═══════════════════════════════════════════

      LAYOUT: bullets
        Khi nào dùng: 3–4 điểm chính, mỗi điểm độc lập. TỐT NHẤT là 3 items.
        Format: mỗi dòng "- Tiêu đề ngắn (tối đa 5-6 từ) :: Mô tả chi tiết 1-2 câu"
        TIÊU ĐỀ phải NGẮN: tối đa 20 ký tự / 4-5 từ. Đây là headline, không phải câu. NGHIÊM CẤM viết dài hơn 20 ký tự.
        Nếu không có "::" → chỉ hiển thị title ngắn
        Ví dụ:
        - Khó tìm quán uy tín :: Người dùng phải lọc thủ công giữa hàng nghìn quán không liên quan trên các app giao đồ ăn hiện có.
        - Thiếu bộ lọc chuyên biệt :: Không có công cụ phân loại theo phong cách ăn hay nguy cơ lẫn nguyên liệu động vật.
        - Quán nhỏ thiếu kênh số :: Nhiều quán ăn chay gia đình chưa có kênh tiếp cận khách hàng trực tuyến hiệu quả.

      LAYOUT: stats
        Khi nào dùng: 2 con số KPI quan trọng + biểu đồ tăng trưởng (stats+chart combo).
        TỐI ĐA 2 items stats. GIÁ TRỊ phải NGẮN (tối đa 6 ký tự): "50K+", "200K", "87%".
        MÔ TẢ phải ngắn: tối đa 8 từ.
        KẾT HỢP CHART: Thêm CHART_ITEMS dạng "- SỐ :: NHÃN" (tối đa 6 điểm) và CHART_LABEL.
        QUY TẮC: Tất cả CHART_ITEMS phải > 0, thể hiện xu hướng tăng/thay đổi rõ ràng — KHÔNG để giá trị 0.
        THÊM CHART_Y_LABEL (đơn vị trục Y, ngắn gọn) và CHART_X_LABEL (tên trục X) để dễ đọc.
        Stats hiển thị bên TRÁI (dark cards), chart bên PHẢI.
        Ví dụ:
        - 50K+ :: Người dùng hoạt động hàng tháng (MAU)
        - 200K :: USD/tháng · Tổng giá trị giao dịch (GMV)
        CHART_LABEL: Người dùng hoạt động hàng tháng (MAU, nghìn)
        CHART_Y_LABEL: Nghìn người
        CHART_X_LABEL: Tháng
        CHART_ITEMS:
        - 8 :: T1
        - 16 :: T2
        - 24 :: T3
        - 33 :: T4
        - 42 :: T5
        - 50 :: T6

      LAYOUT: chart
        Khi nào dùng: so sánh theo thời gian, tiến độ tăng trưởng
        Format: mỗi dòng "- SỐ :: NHÃN" (tối đa 6 cột, dùng STYLE: chart_type=line hoặc chart_type=bar)
        QUY TẮC QUAN TRỌNG: TẤT CẢ các giá trị phải > 0 và có sự chênh lệch rõ ràng. KHÔNG dùng 0 làm giá trị.
        Nếu dữ liệu thực tế không có → dùng giá trị ƯỚC TÍNH hợp lý với xu hướng rõ ràng.
        BẮT BUỘC thêm CHART_Y_LABEL (đơn vị/tên trục Y, ngắn gọn ≤4 từ) và CHART_X_LABEL (tên trục X, ngắn gọn ≤4 từ).
        Ví dụ (xu hướng tăng):
        CHART_Y_LABEL: Triệu đồng
        CHART_X_LABEL: Quý
        - 45 :: Quý 1
        - 62 :: Quý 2
        - 78 :: Quý 3
        - 91 :: Quý 4

      LAYOUT: donut
        Khi nào dùng: phân bổ ngân sách, tỷ lệ phần trăm, cơ cấu
        Format: mỗi dòng "- SỐ :: NHÃN NGẮN :: Giá trị (VD: 150.000 USD)"
        NHÃN phải NGẮN (tối đa 5 từ). Chi tiết chỉ là con số tiền, KHÔNG viết mô tả dài.
        Thêm CENTER: dòng trung tâm (VD: "CENTER: 500.000 :: USD")
        Ví dụ:
        - 30 :: Công nghệ & Sản phẩm :: 150.000 USD
        - 35 :: Marketing & Thu hút :: 175.000 USD
        - 20 :: Mở rộng thị trường :: 100.000 USD
        - 15 :: Vận hành & Nhân sự :: 75.000 USD
        CENTER: 500.000 :: USD

      LAYOUT: two-col
        Khi nào dùng: so sánh 2 phía (pros/cons, trước/sau, lý thuyết/thực tế)
        Format: dòng đầu "- HEADERS: Tiêu đề cột trái | Tiêu đề cột phải"
        Sau đó xen kẽ "- COL1: nội dung" và "- COL2: nội dung"
        Ví dụ:
        - HEADERS: Phương pháp cũ | Phương pháp mới
        - COL1: Học thuộc lòng thụ động
        - COL2: Học chủ động qua thực hành
        - COL1: Ít tương tác, 1 chiều
        - COL2: Collaborative, 2 chiều

      LAYOUT: timeline
        Khi nào dùng: quy trình tuần tự, roadmap, các giai đoạn (tối đa 4 bước)
        Format: mỗi dòng "- TÊN BƯỚC NGẮN :: Mô tả chi tiết 1 câu"
        Ví dụ:
        - Đánh giá :: Phân tích năng lực hiện tại và xác định gap
        - Thiết kế :: Xây dựng lộ trình học cá nhân hóa
        - Triển khai :: Học theo lộ trình với mentor hỗ trợ
        - Đánh giá :: Đo lường kết quả và điều chỉnh

      LAYOUT: pillars
        Khi nào dùng: 3–4 trụ cột/chiến lược/nhóm nội dung song song (vision, giá trị, framework)
        Format: mỗi dòng "- TÊN TRỤ CỘT :: bullet1 | bullet2 | bullet3"
        Ví dụ:
        - Chất lượng giảng dạy :: Áp dụng AI tools toàn diện | Đào tạo giáo viên định kỳ | Chuẩn hóa giáo án
        - Trải nghiệm học sinh :: Học cá nhân hóa | Gamification | Phản hồi tức thì
        - Hạ tầng công nghệ :: LMS hiện đại | Phân tích dữ liệu học tập | Tích hợp AI

      LAYOUT: agenda
        Khi nào dùng: slide mục lục/agenda, liệt kê 4–8 chủ đề sẽ trình bày
        Format: mỗi dòng "- SỐ_THỨ_TỰ :: TÊN CHỦ ĐỀ :: Mô tả ngắn 1 câu"
        Ví dụ:
        - 01 :: Tổng quan chương trình :: Cấu trúc và mục tiêu học tập
        - 02 :: Phương pháp giảng dạy :: Approach và framework áp dụng
        - 03 :: Kết quả đo lường :: KPI và cách đánh giá

      LAYOUT: roles
        Khi nào dùng: đội ngũ sáng lập, 2–3 thành viên chủ chốt
        Format: mỗi dòng "- Tên Người (Title Case) :: Co-Founder & Chức vụ :: Bio 1-2 câu ngắn"
        TÊN phải viết Title Case (Nguyễn Minh Anh), KHÔNG viết ALL CAPS.
        Bio chỉ 1-2 câu ngắn gọn (tối đa 25 từ).
        Ví dụ:
        - Nguyễn Minh Anh :: Co-Founder & CEO :: 10 năm vận hành chuỗi F&B, từng phát triển mạng lưới hơn 200 điểm bán tại Việt Nam.
        - Trần Quốc Bảo :: Co-Founder & CTO :: 8 năm xây dựng nền tảng di động quy mô triệu người dùng cho các startup công nghệ.
        - Lê Thảo My :: Co-Founder & COO :: Chuyên gia tăng trưởng, từng dẫn dắt chiến lược marketing cho startup thương mại điện tử.

      LAYOUT: okr
        Khi nào dùng: mục tiêu và kết quả then chốt, OKR, KPI (3–5 objectives)
        Format: mỗi dòng "- O{N} Tên mục tiêu :: Key result 1 | Key result 2 | Key result 3"
        Ví dụ:
        - O1 Chất lượng giảng dạy :: CSAT giáo viên ≥ 4.5/5 | 100% bài học đạt chuẩn | Tỷ lệ pass ≥ 85%
        - O2 Kết quả học sinh :: Điểm trung bình tăng ≥ 20% | 90% hoàn thành khóa học | NPS ≥ 50

      LAYOUT: principles
        Khi nào dùng: nguyên tắc làm việc, giá trị văn hóa, quy tắc vận hành (4–6 items)
        Format: mỗi dòng "- TIÊU ĐỀ NGẮN :: Mô tả 1-2 câu về ý nghĩa và cách áp dụng"
        Ví dụ:
        - Minh bạch :: Chia sẻ thông tin cởi mở — không có surprises, không có hidden agenda
        - Trách nhiệm :: Mỗi người rõ ownership với task của mình, không đổ lỗi
        - Cải tiến liên tục :: Học hỏi từ mỗi sprint, apply cải tiến ngay lập tức

      ═══════════════════════════════════════════
      HƯỚNG DẪN CHỌN LAYOUT:
      ═══════════════════════════════════════════

      Chọn layout PHÙ HỢP NHẤT với nội dung của từng slide — không có thứ tự cố định.
      Hãy để nội dung quyết định layout:
      - Vấn đề thị trường, giải pháp, tính năng → bullets (PHẢI CÓ ĐÚNG 3 items với ::, KHÔNG ĐƯỢC ÍT HƠN 3)
      - Tăng trưởng, KPI → stats (2 stats + chart_items combo)
      - Phân bổ ngân sách, tỷ lệ % → donut
      - Mô hình kinh doanh, nguồn thu → pillars (PHẢI CÓ ĐÚNG 4 trụ cột, KHÔNG ĐƯỢC ÍT HƠN 4, mỗi trụ 2-3 bullets)
      - Nhiều vai trò, bộ phận → roles
      - Mục tiêu, key results → okr
      - Quy trình tuần tự → timeline
      - 2 phía so sánh → two-col
      - Slide mở đầu overview → agenda
      - Giá trị, nguyên tắc → principles
      - KHÔNG dùng two-col cho mô hình kinh doanh — dùng pillars thay vào

      ═══════════════════════════════════════════
      TÙY CHỌN STYLE (dòng STYLE: tùy chọn, dùng dấu phẩy ngăn cách):
      ═══════════════════════════════════════════

      STYLE cho phép kiểm soát thiết kế TỪNG slide. Nếu không có dòng STYLE, dùng mặc định.
      Format: STYLE: key1=value1, key2=value2

      Các thuộc tính:
      - category=TÊN_NHÓM       → Nhãn nhỏ phía trên title. BẮT BUỘC cho mọi content slide.
      - bg=dark|light|custom    → Nền tối hoặc sáng. Mặc định: light
      - bg_color=#RRGGBB        → Màu background tùy chỉnh (hex). Dùng khi muốn màu đặc biệt, VD: bg_color=#F0F4FF. Ưu tiên hơn bg=
      - chart_type=line|bar     → Loại biểu đồ (chỉ cho LAYOUT: chart). Mặc định: bar
      - icon=TÊN_ICON           → Icon cho cover/summary. Chọn 1 trong: search, store, check, clock, person, people, rocket, code, chart, money, percent, megaphone, crown, lightbulb, shield, star, heart, globe, target, handshake, leaf, phone, truck, briefcase, coins, wallet, calculator, invoice, bank, growth, investment, contract, instagram, twitter, facebook, youtube, linkedin, tiktok, rss, team, user_plus, id_card, graduation, pencil, notebook, certificate, heartbeat, cross, pill, ai, chip, robot, cloud_upload, terminal, network, warehouse, shipping, route, calendar, checklist, workflow, tree, recycle, puzzle, filter, zoom_in, external_link, check_circle, x_circle
      - cover_style=left|centered|minimal → Kiểu bố cục cover (chỉ cho slide cover):
          left: icon+title bên trái, decorative circles bên phải (classic)
          centered: icon+title ở giữa, trang trọng (phù hợp corporate, giáo dục)
          minimal: chỉ title lớn, không icon, sạch sẽ (phù hợp báo cáo, engineering)
      - summary_style=cta|quote|minimal → Kiểu bố cục summary (chỉ cho slide cuối):
          cta: icon + nút CTA + contact (phù hợp pitch deck, đề xuất)
          quote: câu trích dẫn lớn + divider (phù hợp bài giảng, truyền cảm hứng)
          minimal: icon nhỏ + title + danh sách text (phù hợp báo cáo, nội bộ)

      Ví dụ:
      STYLE: category=Vấn đề thị trường
      STYLE: category=Đội ngũ, bg=light
      STYLE: category=PITCH DECK, bg=dark, cover_style=left, icon=rocket
      STYLE: bg=dark, summary_style=cta, icon=handshake

      TIÊU CHUẨN CHẤT LƯỢNG (RẤT QUAN TRỌNG — PHẢI TUÂN THỦ):

      ═══ QUY TẮC NỘI DUNG SỐ 1 ═══
      TOÀN BỘ nội dung slide PHẢI bám sát prompt/chủ đề người dùng yêu cầu.
      KHÔNG ĐƯỢC bịa thông tin, sao chép ví dụ từ system prompt, hoặc thêm chi tiết không liên quan.
      Nếu prompt nói về "Engineering Q2 Report" thì KHÔNG được có "Gọi vốn Series A".
      Nếu prompt nói về "Onboarding nhân viên" thì KHÔNG được có số liệu tài chính bịa.
      Mỗi bullet, số liệu, tên riêng đều phải suy ra được từ prompt người dùng.

      ═══ QUY TẮC ĐỘ DÀI TEXT (CHỐNG TRÀN) ═══
      - TITLE content slide: tối đa 55 ký tự
      - Mỗi bullet (trước ::): tối đa 35 ký tự
      - Mỗi mô tả (sau ::): tối đa 80 ký tự (1-2 câu ngắn)
      - FOOTER: tối đa 80 ký tự
      - NOTE: tối đa 90 ký tự
      - Timeline step: tối đa 25 ký tự, desc tối đa 60 ký tự
      - Stats label: tối đa 30 ký tự
      Nếu nội dung dài hơn, PHẢI tóm tắt ngắn gọn hơn. KHÔNG BAO GIỜ viết quá giới hạn.

      ═══ QUY TẮC COVER (slide đầu tiên) ═══
      - TITLE = TÊN DỰ ÁN hoặc CHỦ ĐỀ CHÍNH (1–5 từ, lấy trực tiếp từ prompt người dùng)
      - SUBTITLE = Mô tả 1 câu italic giải thích nội dung bài thuyết trình
      - STYLE BẮT BUỘC gồm: category, bg=dark, cover_style, icon
        + cover_style: chọn phù hợp chủ đề (left cho pitch/startup, centered cho corporate/giáo dục, minimal cho báo cáo/engineering)
        + icon: chọn icon phù hợp nội dung (leaf cho môi trường, rocket cho startup, code cho tech, lightbulb cho giáo dục, chart cho tài chính...)
      - Bullets = 2 thông tin CỤ THỂ rút từ prompt. KHÔNG bịa thông tin.
      - FOOTER = thông tin liên hệ nếu có
      - TUYỆT ĐỐI KHÔNG dùng emoji trên cover

      ═══ QUY TẮC NỘI DUNG ═══
      - Bullets dùng format "Tiêu đề [icon=TÊN] :: Mô tả chi tiết" — phần mô tả 1-2 câu ngắn gọn, có ngữ cảnh
        + [icon=TÊN] BẮT BUỘC cho mọi bullet. Chọn icon phù hợp ngữ nghĩa với nội dung bullet đó.
        + Danh sách icon: search, store, check, clock, person, people, rocket, code, chart, money, percent, megaphone, crown, lightbulb, shield, star, heart, globe, target, handshake, leaf, phone, truck, fire, bolt, lock, eye, flag, award, cube, layers, settings, share, book, camera, music, map, tools, diamond, briefcase, coins, wallet, calculator, invoice, bank, growth, investment, contract, rss, team, user_plus, id_card, graduation, pencil, notebook, certificate, heartbeat, cross, pill, ai, chip, robot, cloud_upload, terminal, network, warehouse, shipping, route, calendar, checklist, workflow, tree, recycle, puzzle, filter, zoom_in, external_link, check_circle, x_circle, bell, thumbs_up, smile, trending_up, bar_chart, pie_chart, gift, shopping_cart, credit_card, tag, database, server, refresh, info, help, alert, bike, plane, building, hospital, school, car, compass, navigation, video, mic, headphones, send, download, upload, wifi, bluetooth, cpu, monitor, smartphone, printer, mail
        + Brand icons (dùng khi nhắc đến nền tảng cụ thể): facebook, instagram, youtube, tiktok, linkedin, twitter, zalo, shopee, google, whatsapp, telegram
        + Ví dụ: "Chi phí giảm 90% [icon=chart] :: Từ 0.37 USD/kWh năm 2010 xuống 0.04 USD/kWh năm 2023"
        + Ví dụ: "Năng lượng tái tạo [icon=leaf] :: Chiếm 30% sản lượng điện toàn cầu năm 2023"
        + Ví dụ: "Bảo mật dữ liệu [icon=shield] :: Mã hóa AES-256 end-to-end cho mọi giao dịch"
      - Số liệu phải CỤ THỂ và có nguồn nếu có trong prompt
      - KHÔNG dùng emoji bất kỳ đâu trong nội dung
      - TITLE content slide: viết thường tự nhiên, truyền tải insight chính

      ═══ QUY TẮC LAYOUT ═══
      - KHÔNG dùng bullets cho 3 slide liên tiếp — xen kẽ đa dạng
      - Mỗi item trong pillars/roles: ít nhất 3 bullets sau "::"
      - STYLE: category=... BẮT BUỘC cho mọi content slide
      - Dùng FOOTER cho nguồn dữ liệu (VD: "Nguồn: Nielsen Vietnam 2023, Statista")
      - Dùng FOOTER cho disclaimer khi cần (VD: "* Thông tin minh hoạ — thay bằng dữ liệu thật trước khi gửi")
      - Slide cuối PHẢI là slide kết thúc có ý nghĩa — chọn đúng loại theo bảng bên dưới

      ═══ QUY TẮC SUMMARY (slide cuối) ═══
      - TITLE = câu kết thúc phù hợp với loại presentation (xem bảng dưới)
      - Bullets: nội dung phù hợp với summary_style
      - STYLE BẮT BUỘC: bg=dark, summary_style, icon
        + icon: chọn giống hoặc liên quan icon cover

      CHỌN summary_style THEO LOẠI PRESENTATION:
      ┌─────────────────────┬───────────────┬──────────────────────────────────────────┐
      │ Loại presentation   │ summary_style │ TITLE gợi ý                              │
      ├─────────────────────┼───────────────┼──────────────────────────────────────────┤
      │ Pitch deck, gọi vốn │ cta           │ "Hãy cùng xây dựng tương lai"           │
      │ Sales, đề xuất      │ cta           │ "Sẵn sàng bắt đầu?"                     │
      │ Hội thảo, training  │ qna           │ "Câu hỏi & Thảo luận"                   │
      │ Lớp học, giảng dạy  │ qna           │ "Q&A — Hỏi bất cứ điều gì"             │
      │ Keynote, TED-style  │ thankyou      │ "Cảm ơn bạn đã lắng nghe"              │
      │ Sự kiện, workshop   │ thankyou      │ "Xin cảm ơn"                            │
      │ Báo cáo nội bộ      │ minimal       │ "Tóm tắt & Bước tiếp theo"              │
      │ Nghiên cứu, phân tích│ quote        │ Trích dẫn từ chuyên gia liên quan       │
      └─────────────────────┴───────────────┴──────────────────────────────────────────┘
      Bullets của summary_style:
      - cta: [CTA chính] | [email/website] | [số điện thoại nếu có]
      - qna: ["Đặt câu hỏi ngay"] | [thông tin liên hệ sau buổi] | [tài liệu tham khảo]
      - thankyou: [tên presenter/tổ chức] | [website hoặc mạng xã hội] | [lời cảm ơn ngắn]
      - quote: trích dẫn 1 câu từ chuyên gia/nhà lãnh đạo liên quan chủ đề
      - minimal: 2–3 next steps cụ thể
    PROMPT
  end

  def generic_system
    "Bạn là trợ lý tạo nội dung giáo dục/đào tạo chuyên nghiệp. Trả lời bằng tiếng Việt với markdown rõ ràng."
  end

  def generic_user
    type_label = { "outline" => "dàn ý chi tiết", "lesson_plan" => "giáo án / kế hoạch buổi học" }[@outline.output_type] || "dàn ý"
    "Tạo #{type_label} cho chủ đề: \"#{@outline.title}\"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.\n\nYêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}\n\nTạo nội dung đầy đủ, có cấu trúc rõ ràng."
  end

  # ── Slide parsing & HTML viewer ─────────────────────────────────────────────

  def parse_slides(text)
    @slide_theme = "original"
    if @user_color
      # User specified a color in their prompt — always use it
      @slide_color = @user_color
    else
      # No color in prompt — use original theme's default accent (#D4A24C), ignore AI suggestion
      @slide_color = nil
    end

    raw = text.scan(/---SLIDE---(.*?)---END---/m).flatten
    return [] if raw.empty?

    raw.map do |s|
      title    = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      subtitle = s[/SUBTITLE:\s*(.+)/, 1]&.strip || ""
      layout   = s[/LAYOUT:\s*(\S+)/, 1]&.strip&.downcase || "bullets"
      body     = s[/BODY:\n(.*?)(?:\nSTYLE:|\nFOOTER:|\nNOTE:|\z)/m, 1]&.strip || ""
      style_raw = s[/STYLE:\s*(.+)/, 1]&.strip || ""
      footer   = s[/FOOTER:\s*(.+)/, 1]&.strip || ""
      note     = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      lines  = body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)

      style = {}
      style_raw.split(",").each do |pair|
        k, v = pair.split("=", 2).map(&:strip)
        next unless k.present? && v.present?
        style[k] = case v
                    when "true" then true
                    when "false" then false
                    else v
                    end
      end

      slide = { "title" => title, "layout" => layout, "note" => note }
      slide["subtitle"] = subtitle if subtitle.present?
      slide["footer"] = footer if footer.present?
      slide["style"] = style if style.any?

      case layout
      when "stats"
        chart_label_line = body[/CHART_LABEL:\s*(.+)/, 1]&.strip
        chart_y_label    = body[/CHART_Y_LABEL:\s*(.+)/, 1]&.strip
        chart_x_label    = body[/CHART_X_LABEL:\s*(.+)/, 1]&.strip
        chart_section = body[/CHART_ITEMS:\n(.*?)(?:\nSTYLE:|\nFOOTER:|\nCHART_LABEL:|\nCHART_Y_LABEL:|\nCHART_X_LABEL:|\z)/m, 1]
        stat_body = body.sub(/CHART_LABEL:.*$/m, "").sub(/CHART_ITEMS:\n.*\z/m, "").strip
        stat_lines = stat_body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)
        slide["items"] = stat_lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0], "label" => parts[1] || "" }
        end
        if chart_section.present?
          chart_lines = chart_section.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)
          slide["chart_items"] = chart_lines.map do |l|
            parts = l.split("::", 2).map(&:strip)
            { "value" => parts[0].to_f, "label" => parts[1] || "" }
          end
          slide["chart_label"]   = chart_label_line || ""
          slide["chart_y_label"] = chart_y_label || ""
          slide["chart_x_label"] = chart_x_label || ""
        end
        slide["bullets"] = stat_lines
      when "chart"
        slide["chart_y_label"] = body[/CHART_Y_LABEL:\s*(.+)/, 1]&.strip || ""
        slide["chart_x_label"] = body[/CHART_X_LABEL:\s*(.+)/, 1]&.strip || ""
        chart_lines = lines.reject { |l| l =~ /\ACHART_[XY]_LABEL:/i }
        slide["items"] = chart_lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0].to_f, "label" => parts[1] || "" }
        end
        slide["bullets"] = chart_lines
      when "donut"
        center_line = lines.find { |l| l.start_with?("CENTER:") }
        data_lines = lines.reject { |l| l.start_with?("CENTER:") }
        slide["items"] = data_lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          { "value" => parts[0].to_f, "label" => parts[1] || "", "detail" => parts[2] || "" }
        end
        if center_line
          cp = center_line.sub("CENTER:", "").split("::", 2).map(&:strip)
          slide["center_text"] = cp[0] || ""
          slide["center_sub"] = cp[1] || ""
        end
        slide["bullets"] = lines
      when "two-col"
        headers_line = lines.find { |l| l.start_with?("HEADERS:") }
        headers = headers_line ? headers_line.sub("HEADERS:", "").split("|").map(&:strip) : ["", ""]
        col1 = lines.select { |l| l.start_with?("COL1:") }.map { |l| l.sub("COL1:", "").strip }
        col2 = lines.select { |l| l.start_with?("COL2:") }.map { |l| l.sub("COL2:", "").strip }
        slide["headers"] = headers
        slide["col1"] = col1
        slide["col2"] = col2
        slide["bullets"] = lines.reject { |l| l.start_with?("HEADERS:") }
      when "timeline"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "step" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip, "desc" => parts[1] || "" }
        end
        slide["bullets"] = lines
      when "pillars"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          bullets = (parts[1] || "").split("|").map(&:strip).reject(&:empty?)
          { "title" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip, "bullets" => bullets }
        end
        slide["bullets"] = lines
      when "agenda"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          { "num" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip,
            "title" => parts[1]&.gsub(/\s*\[icon=[a-z_]+\]/i, "")&.strip || "",
            "desc" => parts[2] || "" }
        end
        slide["bullets"] = lines
      when "roles"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          bullets = (parts[2] || "").split("|").map(&:strip).reject(&:empty?)
          { "role" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip,
            "type" => parts[1]&.gsub(/\s*\[icon=[a-z_]+\]/i, "")&.strip || "",
            "bullets" => bullets }
        end
        slide["bullets"] = lines
      when "okr"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          krs = (parts[1] || "").split("|").map(&:strip).reject(&:empty?)
          { "objective" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip, "krs" => krs }
        end
        slide["bullets"] = lines
      when "principles"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "title" => parts[0].gsub(/\s*\[icon=[a-z_]+\]/i, "").strip, "desc" => parts[1] || "" }
        end
        slide["bullets"] = lines
      else
        has_desc = lines.any? { |l| l.include?("::") }
        if has_desc
          slide["bullet_items"] = lines.map do |l|
            parts = l.split("::", 2).map(&:strip)
            raw_title = parts[0]
            icon_match = raw_title.match(/\[icon=([a-z_]+)\]/i)
            icon = icon_match ? icon_match[1].downcase : nil
            clean_title = raw_title.gsub(/\s*\[icon=[a-z_]+\]/i, "").strip
            { "title" => clean_title, "desc" => parts[1] || "", "icon" => icon }.compact
          end
        end
        slide["bullets"] = lines.map { |l| l.split("::", 2).first.gsub(/\s*\[icon=[a-z_]+\]/i, "").strip }
      end

      slide
    end
  end

  def slides_to_html(slides)
    return "<p>Không thể tạo slide.</p>" if slides.empty?
    theme = @slide_theme || "blue"
    "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides.to_json)}' data-theme='#{ERB::Util.html_escape(theme)}'></div>"
  end

  # ── PPTX generation ─────────────────────────────────────────────────────────


  # ── Deck schema compiler ─────────────────────────────────────────────────────
  # Produces element-level JSON (inch coords). HTML ×128=px. PPTX reads inches.

  def build_deck_schema(raw_slides, theme_name)
    t = DECK_THEMES[theme_name] || DECK_THEMES["original"]
    # Inject AI-suggested accent color
    if @slide_color&.match?(/\A#[0-9a-fA-F]{6}\z/)
      c = @slide_color
      r = c[1,2].to_i(16); g = c[3,2].to_i(16); b = c[5,2].to_i(16)
      # Very light tint for card backgrounds (5% opacity equivalent)
      lt = "#%02X%02X%02X" % [
        (r + (255 - r) * 0.92).round,
        (g + (255 - g) * 0.92).round,
        (b + (255 - b) * 0.92).round
      ]
      if theme_name == "original"
        # Cover/closing use user color; content slides use primary color for icons/cards
        dk = "#%02X%02X%02X" % [(r * 0.4).round, (g * 0.4).round, (b * 0.4).round]
        md = "#%02X%02X%02X" % [(r * 0.65).round, (g * 0.65).round, (b * 0.65).round]
        t = t.merge(
          "cover_bg"   => "linear-gradient(135deg,#{dk} 0%,#{md} 55%,#{c} 100%)",
          "primary"    => c,
          "primary_dk" => dk,
          "primary_lt" => md,
          "card_icons" => [c, dk, md],
          "card_bgs"   => [lt, lt, lt]
        )
      else
        dk = "#%02X%02X%02X" % [(r * 0.4).round, (g * 0.4).round, (b * 0.4).round]
        md = "#%02X%02X%02X" % [(r * 0.65).round, (g * 0.65).round, (b * 0.65).round]
        t = t.merge(
          "cover_bg"   => "linear-gradient(135deg,#{dk} 0%,#{md} 55%,#{c} 100%)",
          "accent"     => c,
          "primary"    => c,
          "card_icons" => [c, c, c],
          "card_bgs"   => [lt, lt, lt],
          "fg"         => "#FFFFFF",
          "fg_light"   => "rgba(255,255,255,0.75)"
        )
      end
    end
    t = t.merge("name" => theme_name, "fonts" => { "heading" => "Nunito", "body" => "Inter" })
    raw_slides = ensure_closing_slide(raw_slides)
    total = raw_slides.length
    compiled_slides = raw_slides.each_with_index.map do |s, idx|
      stype = idx == 0 ? :cover : (idx == total - 1 ? :summary : :content)
      sl_style = s["style"] || {}
      bg_color_override = sl_style["bg_color"]
      bg_mode = sl_style["bg"]  # "dark", "light", "custom"
      bg = if bg_color_override&.start_with?("#")
             { "type" => "solid", "color" => bg_color_override }
           elsif bg_color_override&.start_with?("gradient:")
             { "type" => "gradient", "value" => bg_color_override.sub("gradient:", "") }
           elsif bg_mode == "dark" || stype != :content
             # Support gradient cover_bg in theme
             cover_bg = t["cover_bg"] || "#1E3A5F"
             cover_bg.start_with?("linear-gradient", "radial-gradient") ?
               { "type" => "gradient", "value" => cover_bg } :
               { "type" => "solid", "color" => cover_bg }
           else
             { "type" => "solid", "color" => "#FFFFFF" }
           end
      els = case stype
            when :cover   then compile_cover(s, t)
            when :summary then compile_summary(s, t, idx, total)
            else               compile_content(s, t, idx, total)
            end
      { "id" => "s#{idx}", "background" => bg, "elements" => els, "raw" => s }
    end
    { "theme" => t, "slides" => compiled_slides }
  end

  def slides_to_html(deck)
    "<div id='slide-deck-root' data-deck='#{ERB::Util.html_escape(deck.to_json)}'></div>"
  end

  private

  # Detect presentation type from title/subject/prompt and return appropriate summary_style
  def detect_closing_style
    text = [@outline.title, @outline.subject, @outline.prompt_input].compact.join(" ").downcase

    # Q&A / training / workshop / classroom
    if text.match?(/đào tạo|tập huấn|training|workshop|lớp học|giảng dạy|bài giảng|học phần|khóa học|onboard|hội thảo|seminar|webinar|bootcamp/)
      return "qna"
    end

    # Pitch deck / sales / proposal / investor
    if text.match?(/pitch|gọi vốn|investor|startup|đầu tư|kêu gọi|series [abc]|seed|funding|đề xuất|proposal|sales|bán hàng|kinh doanh|business plan/)
      return "cta"
    end

    # Keynote / event / conference / ceremony
    if text.match?(/keynote|ted|sự kiện|hội nghị|conference|lễ |kỷ niệm|tổng kết|tốt nghiệp|ra mắt|launch|khai mạc|bế mạc|cảm ơn/)
      return "thankyou"
    end

    # Research / report / analysis
    if text.match?(/báo cáo|report|nghiên cứu|phân tích|analysis|review|tổng hợp|kết quả|quarterly|q[1-4] |annual/)
      return "minimal"
    end

    # Educational / inspirational content
    if text.match?(/giáo dục|education|truyền cảm hứng|inspiration|motivation|văn hóa|giá trị|tầm nhìn|vision|mission/)
      return "quote"
    end

    # Default: thankyou (safe, universal)
    "thankyou"
  end

  # Ensure the last slide is a proper closing slide with the right summary_style and title.
  # If the AI didn't set summary_style, auto-detect and inject it.
  def ensure_closing_slide(raw_slides)
    return raw_slides if raw_slides.size < 2

    last = raw_slides.last.dup
    style = (last["style"] || {}).dup

    # Force bg=dark for summary slide
    style["bg"] ||= "dark"

    # Auto-detect style if AI didn't set one or set an unrecognized value
    valid_styles = %w[cta quote minimal thankyou qna]
    unless valid_styles.include?(style["summary_style"])
      style["summary_style"] = detect_closing_style
    end

    chosen = style["summary_style"]

    # Ensure title matches the style if AI left a generic/empty title
    generic_titles = ["", "kết luận", "tóm tắt", "summary", "conclusion", "cảm ơn", "q&a", "closing"]
    title_lower = (last["title"] || "").downcase.strip
    if title_lower.empty? || generic_titles.any? { |g| title_lower == g }
      last["title"] = case chosen
                      when "qna"      then "Câu hỏi & Thảo luận"
                      when "thankyou" then "Cảm ơn bạn đã lắng nghe"
                      when "quote"    then last["title"].presence || "Cảm ơn"
                      when "minimal"  then "Bước tiếp theo"
                      else                 "Sẵn sàng bắt đầu?"
                      end
    end

    # Ensure icon is set
    style["icon"] ||= case chosen
                      when "qna"      then "people"
                      when "thankyou" then "heart"
                      when "cta"      then "rocket"
                      when "minimal"  then "flag"
                      else                 "star"
                      end

    last["style"] = style
    raw_slides[0..-2] + [last]
  end

  # Strip [icon=name] tag from title and extract icon — handles both raw AI output
  # and already-parsed bullet_items that may still contain the tag in title.
  # Auto-map platform/brand names → brand icons (fallback when AI doesn't tag)
  BRAND_TITLE_ICONS = {
    /\bfacebook\b/i   => "facebook",
    /\binstagram\b/i  => "instagram",
    /\byoutube\b/i    => "youtube",
    /\btiktok\b/i     => "tiktok",
    /\blinkedin\b/i   => "linkedin",
    /\btwitter\b/i    => "twitter",
    /\bzalo\b/i       => "zalo",
    /\bshopee\b/i     => "shopee",
    /\bgoogle\b/i     => "google",
    /\bwhatsapp\b/i   => "whatsapp",
    /\btelegram\b/i   => "telegram",
    /\bx\.com\b/i     => "twitter",
  }.freeze

  def normalize_bullet_items(items)
    items.map do |it|
      title = it["title"].to_s
      icon_in_title = title.match(/\[icon=([a-z_]+)\]/i)
      icon = it["icon"] || (icon_in_title && icon_in_title[1].downcase)
      clean = title.gsub(/\s*\[icon=[a-z_]+\]/i, "").strip
      # Auto-detect brand/platform names when no icon tagged
      unless icon
        BRAND_TITLE_ICONS.each { |pat, name| icon = name if clean.match?(pat) }
      end
      it.merge("title" => clean, "icon" => icon).compact
    end
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  def el_text(id, x, y, w, h, content, style = {}, z: 2)
    { "id" => id, "type" => "text", "x" => x, "y" => y, "w" => w, "h" => h, "z" => z,
      "content" => content.to_s, "style" => style }
  end

  def el_rect(id, x, y, w, h, fill, z: 0, radius: 0, opacity: 1, stroke: nil, sw: 0)
    s = { "fill" => fill, "borderRadius" => radius, "opacity" => opacity }
    s["stroke"] = stroke if stroke
    s["strokeWidth"] = sw if sw > 0
    { "id" => id, "type" => "rect", "x" => x, "y" => y, "w" => w, "h" => h, "z" => z, "style" => s }
  end

  def el_ellipse(id, x, y, w, h, fill, z: 0, opacity: 1)
    { "id" => id, "type" => "ellipse", "x" => x, "y" => y, "w" => w, "h" => h, "z" => z,
      "style" => { "fill" => fill, "opacity" => opacity } }
  end

  def el_icon(id, x, y, size, icon, color, bg, z: 2, radius: "50%")
    { "id" => id, "type" => "icon", "x" => x, "y" => y, "w" => size, "h" => size, "z" => z,
      "icon" => icon, "style" => { "color" => color, "bgColor" => bg, "borderRadius" => radius } }
  end

  def el_line(id, x1, y1, x2, y2, color, width: 0.03, z: 1)
    { "id" => id, "type" => "line", "x" => x1, "y" => y1, "w" => x2 - x1, "h" => y2 - y1, "z" => z,
      "style" => { "stroke" => color, "strokeWidth" => width } }
  end

  def el_chart(id, x, y, w, h, chart_type, data, label: nil, theme: nil, y_label: nil, x_label: nil)
    el = { "id" => id, "type" => "chart_#{chart_type}", "x" => x, "y" => y, "w" => w, "h" => h, "z" => 2,
           "chart" => { "type" => chart_type, "data" => data, "label" => label,
                        "y_label" => y_label, "x_label" => x_label } }
    # Embed theme colors so PPTX generator can use them without a separate lookup
    el["_theme_colors"] = theme["card_icons"] if theme
    el
  end

  def heading_style(size, color: "#1F2A44", align: "left", weight: 700, line_height: 1.2)
    { "fontFamily" => "Nunito", "fontSize" => size, "fontWeight" => weight,
      "color" => color, "align" => align, "lineHeight" => line_height }
  end

  def body_style(size, color: "#1F2A44", align: "left", weight: 400, line_height: 1.5)
    { "fontFamily" => "Inter", "fontSize" => size, "fontWeight" => weight,
      "color" => color, "align" => align, "lineHeight" => line_height }
  end

  def common_header(s, t, idx, total)
    els = []
    cat = s.dig("style", "category") || ""
    els << el_text("cat", 0, 0.35, SW, 0.30, cat,
      heading_style(11, color: t["accent"], align: "center").merge(
        "textTransform" => "uppercase", "letterSpacing" => 2)) if cat.present?
    els << el_text("title", 0, 0.68, SW, 0.90, s["title"] || "",
      heading_style(22, align: "center"), z: 2)
    if s["note"].present?
      els << el_rect("note_bg", LM, 4.45, CW, 0.68, t["card_bgs"][0], radius: 8)
      els << el_text("note_txt", LM + 0.15, 4.45, CW - 0.30, 0.68, s["note"],
        body_style(11, weight: 700).merge("valign" => "center"))
    end
    if s["footer"].present?
      els << el_text("footer", LM, SH - 0.28, 8.0, 0.25, s["footer"],
        body_style(7, color: "#94A3B8"), z: 1)
    end
    els << el_text("pg", SW - 1.0, SH - 0.30, 0.90, 0.25,
      "#{(idx+1).to_s.rjust(2,'0')} / #{total.to_s.rjust(2,'0')}",
      body_style(9, color: "#94A3B8", align: "right"), z: 1)
    els
  end

  # ─── Cover ──────────────────────────────────────────────────────────────────

  def compile_cover(s, t)
    style = t["cover_style"] || s.dig("style", "cover_style") || "left"
    icon  = s.dig("style", "icon") || "rocket"
    cat   = s.dig("style", "category") || ""
    fg    = t["fg"] || "#fff"
    fg_lt = t["fg_light"] || t["text_light"]
    els   = []
    # Decorations vary by deco_style
    case t["deco_style"] || "circles"
    when "circles"
      # Two large overlapping translucent circles
      els << el_ellipse("deco1", -1.8, 2.8, 9.0, 9.0, t["accent"],      opacity: 0.30)
      els << el_ellipse("deco2",  7.5, -2.5, 5.5, 5.5, t["primary_dk"], opacity: 0.55)
      els << el_ellipse("deco3",  6.0,  3.5, 3.0, 3.0, t["accent"],     opacity: 0.18)
    when "wave"
      # Sweeping wave bands from bottom-left
      els << el_ellipse("deco1", -3.0, 2.0, 11.0, 7.0, t["primary_dk"], opacity: 0.28)
      els << el_ellipse("deco2",  4.0, 3.8,  8.0, 5.5, t["accent"],     opacity: 0.20)
      els << el_rect("deco3",    -0.5, 5.0, SW + 1, 1.2, t["accent"],   opacity: 0.18)
    when "diagonal"
      # Bold solid right-side panel
      els << el_rect("deco1", SW * 0.55, -0.2, SW * 0.50, SH + 0.4, t["primary_dk"], z: 0, opacity: 0.80)
      els << el_rect("deco2", SW * 0.65, -0.2, SW * 0.38, SH + 0.4, t["accent"],     z: 0, opacity: 0.55)
    when "dots"
      # Dense dot grid right half
      [0, 1, 2, 3, 4].each do |row|
        [0, 1, 2, 3, 4, 5].each do |col|
          op = 0.15 + (col + row) * 0.025
          els << el_ellipse("dot#{row}_#{col}", 5.8 + col * 0.72, 0.3 + row * 0.80, 0.24, 0.24,
            t["primary_lt"], opacity: [op, 0.50].min)
        end
      end
      els << el_ellipse("deco_lg", 8.2, 3.5, 4.5, 4.5, t["accent"], opacity: 0.18)
    when "split"
      # Full right-panel solid color (40% of width) — strongest contrast
      els << el_rect("deco_panel", SW * 0.60, 0, SW * 0.40, SH, t["accent"],     z: 0, opacity: 0.90)
      els << el_rect("deco_edge",  SW * 0.58, 0, 0.06,       SH, t["primary_dk"], z: 1, opacity: 0.70)
      els << el_ellipse("deco_circ", SW * 0.62, -1.0, 3.5, 3.5, "#ffffff", opacity: 0.08)
    when "corner"
      # Giant circle anchored to bottom-right corner
      els << el_ellipse("deco_circ1", 5.5, 1.8, 6.5, 6.5, t["accent"],     opacity: 0.28)
      els << el_ellipse("deco_circ2", 7.0, 2.8, 5.0, 5.0, t["primary_dk"], opacity: 0.45)
      els << el_ellipse("deco_circ3", 8.5, 4.0, 3.0, 3.0, "#ffffff",       opacity: 0.08)
    when "geo"
      # Geometric angular shapes — triangular cutouts
      els << el_rect("geo1", SW * 0.68, -0.2, SW * 0.35, SH * 0.55, t["primary_dk"], z: 0, opacity: 0.70)
      els << el_rect("geo2", SW * 0.78, SH * 0.45, SW * 0.25, SH * 0.60, t["accent"],     z: 0, opacity: 0.60)
      els << el_ellipse("geo3", SW * 0.55, SH * 0.60, 2.5, 2.5, "#ffffff", opacity: 0.07)
    when "none"
      els << el_rect("deco_top", 0, 0,       SW, 0.06, t["accent"], opacity: 0.7)
      els << el_rect("deco_bot", 0, SH - 0.06, SW, 0.06, t["accent"], opacity: 0.7)
    when "clean"
      # No background decorations — pure navy gradient, nothing else
    end

    case style
    when "clean"
      # Centered: category badge pill → big title → divider → subtitle → bullets footer
      badge_w = 3.2
      els << el_rect("badge_bg", (SW - badge_w) / 2, 0.72, badge_w, 0.36, t["accent"], z: 1, radius: 20)
      els << el_text("cat", (SW - badge_w) / 2, 0.72, badge_w, 0.36, cat,
        heading_style(11, color: "#fff", align: "center").merge("textTransform" => "uppercase", "letterSpacing" => 2), z: 2)
      els << el_text("title", 0.60, 1.30, SW - 1.20, 1.80, s["title"] || "",
        heading_style(52, color: fg, align: "center", line_height: 1.05, weight: "800"))
      els << el_line("div", (SW - 2.0) / 2, 3.22, (SW + 2.0) / 2, 3.22, t["accent"])
      els << el_text("sub", 0.70, 3.40, SW - 1.40, 0.55, s["subtitle"] || "",
        body_style(16, color: fg_lt, align: "center"))
      (s["bullets"] || []).first(2).each_with_index do |b, i|
        els << el_text("bul#{i}", LM + i * (CW / 2 + 0.2), 4.50, CW / 2, 0.38, "• #{b}",
          body_style(12, color: fg_lt, align: "center"))
      end
      return els
    when "centered"
      els << el_icon("ico", (SW - 0.90) / 2, 0.55, 0.90, icon, "#fff", t["accent"], radius: "16px")
      els << el_text("cat", 0, 1.60, SW, 0.30, cat,
        heading_style(11, color: t["primary_lt"], align: "center").merge("textTransform" => "uppercase", "letterSpacing" => 2))
      els << el_text("title", 0.80, 2.00, SW - 1.60, 1.40, s["title"] || "",
        heading_style(44, color: fg, align: "center", line_height: 1.1))
      els << el_text("sub", 0.80, 3.50, SW - 1.60, 0.70, s["subtitle"] || "",
        body_style(15, color: fg_lt, align: "center"))
    when "minimal"
      els << el_text("title", 0.80, 1.20, SW - 1.60, 1.80, s["title"] || "",
        heading_style(44, color: fg, align: "left", line_height: 1.1))
      els << el_line("div", LM, 3.20, LM + 2.5, 3.20, t["accent"])
      els << el_text("sub", 0.80, 3.40, SW - 1.60, 0.70, s["subtitle"] || "",
        body_style(15, color: fg_lt))
    else # left
      els << el_icon("ico", 0.70, 0.65, 0.85, icon, "#fff", t["accent"], radius: "14px")
      els << el_text("cat", 0.70, 1.72, 8.0, 0.30, cat,
        heading_style(11, color: t["primary_lt"]).merge("textTransform" => "uppercase", "letterSpacing" => 2))
      els << el_text("title", 0.65, 2.05, 7.50, 1.30, s["title"] || "",
        heading_style(44, color: fg, line_height: 1.1))
      els << el_text("sub", 0.68, 3.40, 7.50, 0.65, s["subtitle"] || "",
        body_style(15, color: fg_lt))
    end

    # Bullets (2 key points)
    (s["bullets"] || []).first(2).each_with_index do |b, i|
      els << el_text("bul#{i}", LM + i * 4.0, 4.55, 3.90, 0.50, "• #{b}",
        body_style(12, color: fg_lt))
    end
    els
  end

  # ─── Summary ────────────────────────────────────────────────────────────────

  def compile_summary(s, t, idx, total)
    style = t["cover_style"] == "minimal" ? "minimal" : (s.dig("style", "summary_style") || "cta")
    icon  = s.dig("style", "icon") || "rocket"
    fg    = t["fg"] || "#fff"
    fg_lt = t["fg_light"] || t["text_light"]
    # Extract key bullets from any layout format the AI may have used
    if (s["bullets"] || []).empty? || s["bullets"].any? { |b| b.to_s.start_with?("COL1:", "COL2:") }
      extracted = []
      extracted += (s["col1"] || []).first(2)
      extracted += (s["col2"] || []).first(2)
      extracted += (s["items"] || []).map { |it| it.is_a?(Hash) ? (it["title"] || it["label"] || it.values.first).to_s : it.to_s }.first(3)
      s = s.merge("bullets" => extracted.reject(&:blank?).first(4)) if extracted.any?
    end
    els   = []
    unless t["deco_style"] == "clean"
      els << el_ellipse("deco1", -2.0, 1.0, 6.5, 6.5, t["accent"], opacity: 0.20)
      els << el_ellipse("deco2", 9.0, -1.5, 4.0, 4.0, t["primary_dk"], opacity: 0.40)
    end

    # clean deco_style: override summary to a clean centered closing slide
    if t["deco_style"] == "clean"
      els << el_text("title", 0.60, 1.60, SW - 1.20, 1.60, s["title"] || "Cảm ơn",
        heading_style(48, color: fg, align: "center", line_height: 1.05, weight: "800"))
      els << el_line("div", (SW - 2.0) / 2, 3.30, (SW + 2.0) / 2, 3.30, t["accent"])
      els << el_text("sub", 0.70, 3.52, SW - 1.40, 0.55, s["subtitle"] || "",
        body_style(15, color: fg_lt, align: "center"))
      (s["bullets"] || []).first(3).each_with_index do |b, i|
        els << el_text("sub#{i}", LM, 4.10 + i * 0.30, CW, 0.28, b,
          body_style(13, color: fg_lt, align: "center"))
      end
      return els
    end

    case style
    when "thankyou"
      els << el_icon("ico", (SW - 1.10) / 2, 0.38, 1.10, icon, "#fff", t["accent"], radius: "50%")
      els << el_text("title", LM, 1.72, CW, 1.50, s["title"] || "Cảm ơn bạn đã lắng nghe",
        heading_style(34, color: fg, align: "center", line_height: 1.15))
      els << el_line("div", (SW - 3.0) / 2, 3.40, (SW + 3.0) / 2, 3.40, t["accent"])
      (s["bullets"] || []).first(3).each_with_index do |b, i|
        els << el_text("sub#{i}", LM, 3.60 + i * 0.30, CW, 0.28, b,
          body_style(13, color: fg_lt, align: "center"))
      end
    when "qna"
      els << el_rect("qbox", (SW - 1.30) / 2, 0.30, 1.30, 1.30, t["accent"], z: 2, radius: 14)
      els << el_text("qmark", (SW - 1.30) / 2, 0.32, 1.30, 1.20, "?",
        heading_style(56, color: "#fff", align: "center", line_height: 1.0), z: 3)
      els << el_text("title", LM, 1.82, CW, 1.40, s["title"] || "Q&A — Hỏi & Đáp",
        heading_style(30, color: fg, align: "center", line_height: 1.2))
      els << el_line("div", (SW - 2.5) / 2, 3.38, (SW + 2.5) / 2, 3.38, t["accent"])
      (s["bullets"] || []).first(3).each_with_index do |b, i|
        els << el_text("bul#{i}", LM, 3.58 + i * 0.30, CW, 0.28, b,
          body_style(13, color: fg_lt, align: "center"))
      end
    when "quote"
      els << el_text("q", 0.70, 0.45, 1.0, 1.0, "“",
        heading_style(72, color: t["primary_lt"], align: "left", line_height: 0.8))
      els << el_text("title", 1.10, 1.30, SW - 2.20, 1.80, s["title"] || "",
        heading_style(28, color: fg, align: "center", line_height: 1.2))
      els << el_line("div", (SW - 2.0) / 2, 3.30, (SW + 2.0) / 2, 3.30, t["accent"])
      (s["bullets"] || []).first(2).each_with_index do |b, i|
        els << el_text("bul#{i}", LM, 3.55 + i * 0.35, CW, 0.30, b,
          body_style(13, color: fg_lt, align: "center"))
      end
    when "minimal"
      els << el_rect("ibox", LM, 0.75, 0.85, 0.85, t["primary"], z: 2, radius: 12)
      els << el_icon("ico_inner", LM + 0.18, 0.85, 0.50, icon, "#fff", t["primary"], z: 3)
      els << el_text("title", LM, 1.80, CW, 1.60, s["title"] || "",
        heading_style(32, color: fg, line_height: 1.15))
      (s["bullets"] || []).first(3).each_with_index do |b, i|
        els << el_text("bul#{i}", LM, 3.55 + i * 0.35, CW, 0.32, b,
          body_style(13, color: fg_lt))
      end
    else # cta
      els << el_icon("ico", (SW - 0.95) / 2, 0.50, 0.95, icon, "#fff", t["accent"], radius: "16px")
      els << el_text("title", LM, 1.70, CW, 1.80, s["title"] || "",
        heading_style(28, color: fg, align: "center", line_height: 1.2))
      if (s["bullets"] || []).any?
        els << el_rect("cta_bg", (SW - 5.10) / 2, 3.10, 5.10, 0.72, t["accent"], z: 2, radius: 10)
        els << el_text("cta_txt", (SW - 5.10) / 2 + 0.15, 3.22, 4.80, 0.48, s["bullets"][0] || "",
          heading_style(16, color: "#fff", align: "center"), z: 3)
        extra = s["bullets"][1..]&.join("   |   ") || ""
        els << el_text("contacts", LM, 4.35, CW, 0.35, extra,
          body_style(12, color: fg_lt, align: "center")) if extra.present?
      end
    end

    els << el_text("pg", SW - 0.90, SH - 0.30, 0.80, 0.25,
      "#{total.to_s.rjust(2,'0')} / #{total.to_s.rjust(2,'0')}",
      body_style(9, color: t["primary_lt"], align: "right"), z: 1)
    els
  end

  # ─── Content ────────────────────────────────────────────────────────────────

  def compile_content(s, t, idx, total)
    has_note = s["note"].present?
    bot = has_note ? 4.35 : 5.10
    layout_els = case (s["layout"] || "bullets")
      when "stats"      then compile_stats(s, t, has_note, bot)
      when "chart"      then compile_chart(s, t, has_note, bot)
      when "donut"      then compile_donut(s, t, has_note, bot)
      when "two-col"    then compile_two_col(s, t, has_note, bot)
      when "timeline"   then compile_timeline(s, t, has_note, bot)
      when "pillars"    then compile_pillars(s, t, has_note, bot)
      when "agenda"     then compile_agenda(s, t, has_note, bot)
      when "roles"      then compile_roles(s, t, has_note, bot)
      when "okr"        then compile_okr(s, t, has_note, bot)
      when "principles" then compile_principles(s, t, has_note, bot)
      else                   compile_bullets(s, t, has_note, bot)
      end
    common_header(s, t, idx, total) + layout_els
  end

  # ─── Bullets ────────────────────────────────────────────────────────────────

  def compile_bullets(s, t, has_note, bot)
    b_items = normalize_bullet_items(s["bullet_items"] || [])
    bullets  = s["bullets"] || []
    els = []
    n = b_items.length

    if n >= 2 && n <= 3
      gap = 0.25; col_w = (CW - gap * (n - 1)) / n
      card_h = has_note ? 2.10 : 2.55
      n.times do |i|
        it = b_items[i]; ac = t["card_icons"][i % 3]; bg = t["card_bgs"][i % 3]
        ico = it["icon"] || "star"
        cx = LM + i * (col_w + gap)
        els << el_rect("card#{i}", cx, 1.80, col_w, card_h, bg, radius: 8)
        els << el_icon("ico#{i}", cx + (col_w - 0.55) / 2, 1.95, 0.55, ico, "#fff", ac)
        els << el_text("ctit#{i}", cx, 2.60, col_w, 0.45, it["title"] || "",
          heading_style(12, color: "#1F2A44", align: "center"))
        els << el_text("cdsc#{i}", cx + 0.10, 3.10, col_w - 0.20, 0.85, it["desc"] || "",
          body_style(9, color: "#5B6478", align: "center")) if (it["desc"] || "").present?
      end
    elsif n >= 4
      avail = bot - 1.80; rh = [[0.85, avail / [n, 8].min].min, 0.45].max
      n.times do |i|
        break if i >= 8
        it = b_items[i]; ac = t["card_icons"][i % 3]
        ico = it["icon"] || "star"; cy = 1.80 + i * rh
        break if cy + 0.44 > bot
        els << el_icon("ico#{i}", LM, cy + 0.02, 0.42, ico, "#fff", ac)
        els << el_text("ctit#{i}", LM + 0.55, cy + 0.04, CW - 0.55, 0.30, it["title"] || "",
          heading_style(12))
        els << el_text("cdsc#{i}", LM + 0.55, cy + 0.32, CW - 0.55, 0.44, it["desc"] || "",
          body_style(9, color: "#5B6478")) if (it["desc"] || "").present?
      end
    elsif bullets.any?
      bn = bullets.length
      if bn <= 3
        gap = 0.20; bw = (CW - gap * (bn - 1)) / bn
        bn.times do |i|
          ac = t["card_icons"][i % 3]
          bx = LM + i * (bw + gap)
          els << el_icon("ico#{i}", bx + (bw - 0.50) / 2, 2.20, 0.50, "star", "#fff", ac)
          els << el_text("btxt#{i}", bx, 2.82, bw, 0.60, bullets[i] || "",
            heading_style(13, color: "#1F2A44", align: "center"))
        end
      else
        avail = bot - 1.80; rh = [[0.65, avail / [bn, 10].min].min, 0.38].max
        bn.times do |i|
          break if i >= 10
          cy = 1.80 + i * rh; break if cy + 0.36 > bot
          ac = t["card_icons"][i % 3]
          els << el_icon("ico#{i}", LM, cy + 0.01, 0.32, "star", "#fff", ac)
          els << el_text("btxt#{i}", LM + 0.42, cy + 0.02, CW - 0.42, 0.30, bullets[i] || "",
            heading_style(12))
        end
      end
    end
    els
  end

  # ─── Stats ──────────────────────────────────────────────────────────────────

  def compile_stats(s, t, has_note, bot)
    items = s["items"] || s["bullets"]&.map { |b| p = b.split("::"); { "value" => p[0]&.strip, "label" => p[1]&.strip || b } } || []
    chart_items = s["chart_items"] || []
    n = items.length; els = []

    if chart_items.length >= 2
      2.times do |i|
        it = items[i] || {}; ac = t["card_icons"][i]
        ch = has_note ? 1.20 : 1.50; cy = 1.70 + i * (ch + 0.15)
        els.concat(stat_card("sc#{i}", LM, cy, 2.90, ch, it["value"], it["label"], ac, t))
      end
      chart_h = bot - 1.70
      els << el_chart("chart", LM + 3.05, 1.70, CW - 3.05, chart_h, "bar", chart_items, label: s["chart_label"], theme: t, y_label: s["chart_y_label"], x_label: s["chart_x_label"])
    elsif n <= 2
      n.times do |i|
        it = items[i]; ac = t["card_icons"][i]
        els.concat(stat_card("sc#{i}", LM + i * (2.90 + 0.15), 1.70, 2.90, 1.50, it["value"], it["label"], ac, t))
      end
    elsif n == 3
      gap = 0.15; cw = (CW - gap * 2) / 3
      n.times do |i|
        it = items[i]; ac = t["card_icons"][i]
        els.concat(stat_card("sc#{i}", LM + i * (cw + gap), 1.70, cw, 1.50, it["value"], it["label"], ac, t))
      end
    else
      gap = 0.15; cw = (CW - gap) / 2; rows = (n / 2.0).ceil
      ch = [[1.35, (3.30 - gap * (rows - 1)) / rows].min, 0.90].max
      [n, 6].min.times do |i|
        it = items[i]; ac = t["card_icons"][i % 3]
        col = i % 2; row = i / 2
        cx = LM + col * (cw + gap); cy = 1.70 + row * (ch + gap)
        els.concat(stat_card("sc#{i}", cx, cy, cw, ch, it["value"], it["label"], ac, t))
      end
    end
    els
  end

  def stat_card(id, x, y, w, h, value, label, accent, t)
    [el_rect("#{id}_bg", x, y, w, h, t["primary_dk"], radius: 8),
     el_rect("#{id}_bar", x, y, 0.06, h, accent, z: 2, radius: 2),
     el_text("#{id}_val", x + 0.15, y + 0.15, w - 0.25, h * 0.55,
       value.to_s, heading_style(30, color: "#fff"), z: 3),
     el_text("#{id}_lbl", x + 0.15, y + h * 0.58, w - 0.25, h * 0.38,
       label.to_s, body_style(9, color: t["primary_xl"]), z: 3)]
  end

  # ─── Chart ──────────────────────────────────────────────────────────────────

  def compile_chart(s, t, has_note, bot)
    items = s["items"] || s["bullets"]&.map { |b| p = b.split("::"); { "value" => p[0].to_f, "label" => p[1]&.strip || b } } || []
    [el_chart("chart", LM, 1.70, CW, bot - 1.70, s.dig("style", "chart_type") || "bar", items, theme: t, y_label: s["chart_y_label"], x_label: s["chart_x_label"])]
  end

  # ─── Donut ──────────────────────────────────────────────────────────────────

  # Must match JS DONUT_FALLBACK palette in renderDonutChart
  DONUT_PALETTE = %w[#f97316 #3b82f6 #22c55e #a855f7 #ef4444 #06b6d4 #f59e0b #ec4899].freeze

  def compile_donut(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || [])
    # Determine per-segment colors (same logic as JS renderer)
    raw_colors = t["card_icons"] || []
    all_same = raw_colors.uniq.length <= 1
    seg_colors = all_same ? DONUT_PALETTE : (raw_colors + DONUT_PALETTE)
    els = [el_chart("donut", LM, 1.65, 4.50, bot - 1.65, "donut", items,
      label: "#{s['center_text']}|#{s['center_sub']}", theme: t)]
    donut_icons = %w[chart leaf rocket globe lightbulb shield]
    legend_start = 1.70; item_h = [[0.80, (bot - legend_start) / [items.length, 1].max].min, 0.42].max
    items.first(8).each_with_index do |it, i|
      ac = seg_colors[i % seg_colors.length]; cy = legend_start + i * item_h
      break if cy + 0.42 > bot
      dot_sz = 0.22
      # Solid color circle dot instead of icon
      els << el_ellipse("ddot#{i}", LM + 4.65, cy + (item_h - dot_sz) / 2.0, dot_sz, dot_sz, ac, z: 2)
      els << el_text("dlbl#{i}", LM + 5.00, cy + 0.04, CW - 5.00, 0.30, it["label"] || "",
        heading_style(10, color: ac))
      els << el_text("ddtl#{i}", LM + 5.00, cy + 0.32, CW - 5.00, 0.26,
        "#{it['value']}%#{it['detail'].present? ? ' · ' + it['detail'] : ''}",
        body_style(9, color: "#5B6478"))
    end
    els
  end

  # ─── Two-col ────────────────────────────────────────────────────────────────

  # Cycle of varied icons used when AI doesn't specify
  COL_ICONS = %w[check leaf rocket chart globe lightbulb shield target heart megaphone].freeze

  def compile_two_col(s, t, has_note, bot)
    col1 = s["col1"] || []; col2 = s["col2"] || []
    headers = s["headers"] || ["", ""]
    gap = 0.30; cw = (CW - gap) / 2; els = []
    [col1, col2].each_with_index do |items, ci|
      cx = LM + ci * (cw + gap)
      header = headers[ci] || ""
      # Outer container for the whole column (header + items)
      col_h = bot - 1.70
      els << el_rect("cbg#{ci}", cx, 1.70, cw, col_h, t["card_bgs"][ci], radius: 8, opacity: 0.55)
      if header.present?
        # Header band with stronger bg
        els << el_rect("hbg#{ci}", cx, 1.70, cw, 0.45, t["card_bgs"][ci], radius: 8, z: 2)
        els << el_text("htxt#{ci}", cx + 0.10, 1.72, cw - 0.20, 0.42, header,
          heading_style(11, color: t["card_icons"][ci]).merge("valign" => "center"), z: 3)
      end
      start_y = header.present? ? 2.22 : 1.85; rh = 0.80
      items.each_with_index do |item, i|
        cy = start_y + i * rh; break if cy + 0.60 > bot
        ac = t["card_icons"][(ci + i) % 3]
        ico = COL_ICONS[(ci * 5 + i) % COL_ICONS.length]
        els << el_icon("ico#{ci}_#{i}", cx + 0.10, cy + 0.02, 0.30, ico, "#fff", ac, z: 3)
        els << el_text("txt#{ci}_#{i}", cx + 0.48, cy, cw - 0.55, 0.70, item,
          body_style(9, line_height: 1.35), z: 3)
      end
    end
    els
  end

  # ─── Timeline ───────────────────────────────────────────────────────────────

  def compile_timeline(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); n = [items.length, 5].min; els = []
    gap = 0.12; step_w = (CW - gap * (n - 1)) / [n, 1].max; card_h = 2.50
    n.times do |i|
      it = items[i]; ac = t["card_icons"][i % 3]; cx = LM + i * (step_w + gap)
      els << el_rect("tbg#{i}", cx, 1.70, step_w, card_h, "#fff", radius: 6, stroke: "#E2E8F0", sw: 0.02)
      els << el_rect("tbar#{i}", cx, 1.70, step_w, 0.05, ac, radius: 2, z: 2)
      els << el_rect("tnum_bg#{i}", cx + (step_w - 0.32) / 2, 1.82, 0.32, 0.32, ac, z: 3, radius: 100)
      els << el_text("tnum#{i}", cx + (step_w - 0.32) / 2, 1.82, 0.32, 0.32, format("%02d", i + 1),
        heading_style(12, color: "#fff", align: "center").merge("valign" => "center"), z: 4)
      els << el_text("tstep#{i}", cx + 0.05, 2.22, step_w - 0.10, 0.38, it["step"] || "",
        heading_style(10, color: ac, align: "center", line_height: 1.2))
      els << el_text("tdsc#{i}", cx + 0.08, 2.62, step_w - 0.16, 1.45, it["desc"] || "",
        body_style(8, color: "#1F2A44", align: "center"))
    end
    els
  end

  # ─── Pillars ────────────────────────────────────────────────────────────────

  def compile_pillars(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); n = items.length; els = []
    cols = n >= 2 ? 2 : 1; rows = (n / 2.0).ceil
    gap_x = 0.30; gap_y = 0.20; col_w = (CW - gap_x * (cols - 1)) / cols
    avail_h = bot - 1.65; card_h = [[2.80, (avail_h - gap_y * (rows - 1)) / [rows, 1].max].min, 1.20].max
    n.times do |i|
      it = items[i]; ac = t["card_icons"][i % 3]; bg = t["card_bgs"][i % 3]
      ico = it["icon"] || "star"
      col = i % cols; row = i / cols
      cx = LM + col * (col_w + gap_x); cy = 1.65 + row * (card_h + gap_y)
      els << el_rect("pbg#{i}", cx, cy, col_w, card_h, bg, radius: 8)
      els << el_icon("pico#{i}", cx + 0.15, cy + 0.15, 0.45, ico, "#fff", ac)
      els << el_text("ptit#{i}", cx + 0.70, cy + 0.17, col_w - 0.85, 0.40, it["title"] || "",
        heading_style(12))
      buls = (it["bullets"] || []).join(" · ")
      els << el_text("pdsc#{i}", cx + 0.15, cy + 0.68, col_w - 0.30, card_h - 0.80, buls,
        body_style(9, color: "#5B6478"))
    end
    els
  end

  # ─── Agenda ─────────────────────────────────────────────────────────────────

  def compile_agenda(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); rh = 0.55; gap = 0.08; els = []
    items.each_with_index do |it, i|
      cy = 1.70 + i * (rh + gap); break if cy + rh > bot
      ac = t["card_icons"][i % 3]
      els << el_rect("abg#{i}", LM, cy, CW, rh, "#fff", radius: 6, stroke: "#E2E8F0", sw: 0.02)
      els << el_rect("anum_bg#{i}", LM + 0.08, cy + 0.11, 0.33, 0.33, ac, z: 2, radius: 100)
      els << el_text("anum#{i}", LM + 0.08, cy + 0.11, 0.33, 0.33, (it["num"] || format("%02d", i + 1)).to_s,
        heading_style(11, color: "#fff", align: "center").merge("valign" => "center"), z: 3)
      els << el_text("atit#{i}", LM + 0.52, cy + 0.10, CW - 0.70, 0.28, it["title"] || "",
        heading_style(12))
      els << el_text("adsc#{i}", LM + 0.52, cy + 0.32, CW - 0.70, 0.18, it["desc"] || "",
        body_style(8, color: "#5B6478")) if (it["desc"] || "").present?
    end
    els
  end

  # ─── Roles ──────────────────────────────────────────────────────────────────

  def compile_roles(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); n = [items.length, 4].min; els = []
    gap = 0.15; col_w = (CW - gap * (n - 1)) / [n, 1].max; card_h = bot - 1.75
    n.times do |i|
      it = items[i]; ac = t["card_icons"][i % 3]
      cx = LM + i * (col_w + gap)
      els << el_rect("rbg#{i}", cx, 1.75, col_w, card_h, "#fff", radius: 6, stroke: "#E2E8F0", sw: 0.02)
      els << el_rect("rtop#{i}", cx, 1.75, col_w, 0.05, ac, radius: 2, z: 2)
      els << el_ellipse("rav#{i}", cx + (col_w - 0.60) / 2, 1.85, 0.60, 0.60, t["card_bgs"][i % 3])
      els << el_icon("ravi#{i}", cx + (col_w - 0.42) / 2, 1.94, 0.42, "person", ac, t["card_bgs"][i % 3])
      els << el_text("rnm#{i}", cx, 2.54, col_w, 0.35, it["role"] || "",
        heading_style(11, color: "#1F2A44", align: "center"))
      els << el_text("rtyp#{i}", cx, 2.88, col_w, 0.28, it["type"] || "",
        body_style(9, color: ac, align: "center", weight: 600))
      buls = (it["bullets"] || []).first(3).join("\n")
      els << el_text("rbio#{i}", cx + 0.10, 3.20, col_w - 0.20, card_h - 1.50, buls,
        body_style(8, color: "#1F2A44", align: "center", line_height: 1.4))
    end
    els
  end

  # ─── OKR ────────────────────────────────────────────────────────────────────

  def compile_okr(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); rh = 0.65; gap = 0.08; els = []
    items.each_with_index do |it, i|
      cy = 1.70 + i * (rh + gap); break if cy + rh > bot
      ac = t["card_icons"][i % 3]
      els << el_rect("okbg#{i}", LM, cy, CW, rh, "#fff", radius: 6, stroke: "#E2E8F0", sw: 0.02)
      els << el_rect("okbar#{i}", LM, cy, 0.05, rh, ac, z: 2, radius: 2)
      els << el_text("okobj#{i}", LM + 0.15, cy + 0.15, 1.60, 0.38, it["objective"] || "",
        heading_style(10, color: ac))
      krs_text = (it["krs"] || []).map { |kr| "✓ #{kr}" }.join("   ")
      els << el_text("kkrs#{i}", LM + 1.80, cy + 0.15, CW - 1.85, 0.38, krs_text,
        body_style(9, color: "#5B6478"))
    end
    els
  end

  # ─── Principles ─────────────────────────────────────────────────────────────

  def compile_principles(s, t, has_note, bot)
    items = normalize_bullet_items(s["items"] || []); els = []
    cols = 2; col_w = (CW - 0.15) / 2; card_h = 0.85; gap_y = 0.12
    items.each_with_index do |it, i|
      col = i % cols; row = i / cols
      cx = LM + col * (col_w + 0.15); cy = 1.70 + row * (card_h + gap_y)
      break if cy + card_h > bot
      ac = t["card_icons"][i % 3]
      principles_icons = %w[target shield rocket lightbulb leaf globe heart megaphone]
      ico = it["icon"].presence || principles_icons[i % principles_icons.length]
      title = it.is_a?(String) ? it : (it["title"] || "")
      desc  = it.is_a?(String) ? "" : (it["desc"] || "")
      els << el_icon("pico#{i}", cx, cy + 0.15, 0.32, ico, "#fff", ac)
      els << el_text("ptit#{i}", cx + 0.42, cy + 0.10, col_w - 0.42, 0.32, title,
        heading_style(12))
      els << el_text("pdsc#{i}", cx + 0.42, cy + 0.42, col_w - 0.42, 0.40, desc,
        body_style(8, color: "#5B6478", line_height: 1.4)) if desc.present?
    end
    els
  end


    def generate_pptx(deck, image_paths: [])
    require "open3"
    deck_data = deck.is_a?(String) ? deck : deck.to_json
    out_path  = Rails.root.join("tmp", "slide_#{@outline.id}_#{Time.now.to_i}.pptx").to_s

    # Pixel-perfect pipeline: render slides to PNG via headless Chrome → assemble PPTX
    if File.exist?(RENDER_SLIDES_JS) && File.exist?(PNGS_TO_PPTX_PY)
      Dir.mktmpdir("vox_pptx_") do |tmpdir|
        json_file = File.join(tmpdir, "deck.json")
        png_dir   = File.join(tmpdir, "pngs")
        File.write(json_file, deck_data)

        # Step 1: render each slide to PNG
        _out, err, status = Open3.capture3("node", RENDER_SLIDES_JS, json_file, png_dir)
        Rails.logger.error "[PPTX:render] #{err}" if err.present?
        unless status.success?
          Rails.logger.error "[PPTX] render_slides.js failed, falling back to legacy"
          return generate_pptx_legacy(deck_data, out_path)
        end

        # Step 2: combine PNGs into PPTX
        _out2, err2, status2 = Open3.capture3("python3", PNGS_TO_PPTX_PY, png_dir, out_path)
        Rails.logger.error "[PPTX:assemble] #{err2}" if err2.present?
        return status2.success? && File.exist?(out_path) ? out_path : nil
      end
    else
      generate_pptx_legacy(deck_data, out_path)
    end
  rescue => e
    Rails.logger.error "[PPTX] #{e.message}"
    nil
  end

  def generate_pptx_legacy(deck_data, out_path)
    return nil unless File.exist?(PPTX_SCRIPT)
    require "open3"
    _out, stderr, status = Open3.capture3("python3", PPTX_SCRIPT, deck_data, out_path)
    Rails.logger.error "[PPTX:legacy] #{stderr}" if stderr.present?
    status.success? && File.exist?(out_path) ? out_path : nil
  end

  def generate_slide_images(pptx_path)
    Dir.mktmpdir do |dir|
      pdf_path = File.join(dir, "slides.pdf")
      system("soffice", "--headless", "--convert-to", "pdf", "--outdir", dir, pptx_path, [:out, :err] => "/dev/null")
      pdf = Dir.glob(File.join(dir, "*.pdf")).first
      return unless pdf

      system("pdftoppm", "-jpeg", "-jpegopt", "quality=85", "-r", "150", pdf, File.join(dir, "slide"))
      jpgs = Dir.glob(File.join(dir, "slide-*.jpg")).sort

      @outline.slide_images.purge if @outline.slide_images.attached?
      jpgs.each_with_index do |jpg, i|
        @outline.slide_images.attach(
          io: File.open(jpg),
          filename: "slide-#{i + 1}.jpg",
          content_type: "image/jpeg"
        )
      end
    end
  rescue => e
    Rails.logger.error "[SlideImages] #{e.message}"
  end

  def attach_pptx(path)
    filename = "#{@outline.title.parameterize}.pptx"
    @outline.pptx_file.attach(
      io: File.open(path),
      filename: filename,
      content_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    )
  ensure
    File.delete(path) rescue nil
  end

  # ── Markdown → HTML ─────────────────────────────────────────────────────────

  def markdown_to_html(text)
    colors = %w[#10b981 #f59e0b #6366f1 #3b82f6 #ec4899]
    ci = 0
    text.gsub(/^## (.+)$/) { c = colors[ci % colors.size]; ci += 1; "<h2 style='border-left:4px solid #{c};padding-left:10px;color:#{c};margin:20px 0 8px'>#{$1}</h2>" }
        .gsub(/^### (.+)$/, '<h3 style="font-weight:700;margin:12px 0 4px;color:#334155">\1</h3>')
        .gsub(/^# (.+)$/,   '<h1 style="font-size:1.3em;font-weight:800;margin:0 0 16px;color:#1e293b">\1</h1>')
        .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        .gsub(/^- (.+)$/,   '<li style="margin:3px 0 3px 16px">\1</li>')
        .gsub(/^(\d+)\. (.+)$/, '<li style="margin:3px 0 3px 16px;list-style:decimal">\2</li>')
        .gsub(/^---$/, '<hr style="border:none;border-top:1px solid #e2e8f0;margin:16px 0">')
        .gsub(/\n\n/, '</p><p style="margin:8px 0">')
        .then { |t| "<p style='margin:8px 0'>#{t}</p>" }
  end
end
