class ContentOutlineGenerator
  PPTX_SCRIPT = Rails.root.join("scripts", "generate_pptx.py").to_s

  def self.call(outline)
    new(outline).call
  end

  def self.ai_edit(outline, edit_prompt)
    new(outline).ai_edit(edit_prompt)
  end

  def initialize(outline)
    @outline = outline
  end

  def call
    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    if @outline.output_type == "slide"
      result = svc.call(system_prompt: slide_system, user_prompt: slide_user, max_tokens: 4000)
      slides = parse_slides(result)
      html   = slides_to_html(slides)
      pptx_path = generate_pptx(slides)
      @outline.update!(content: html, slide_json: slides.to_json, status: :done)
      attach_pptx(pptx_path) if pptx_path
    else
      result = svc.call(system_prompt: generic_system, user_prompt: generic_user, max_tokens: 3000)
      @outline.update!(content: markdown_to_html(result), status: :done)
    end

    cost = @outline.output_type == "slide" ? 5 : 2
    @outline.workspace.active_subscription&.deduct_credits!(cost)
  end

  def ai_edit(edit_prompt)
    current_slides = JSON.parse(@outline.slide_json || "[]")
    svc = ClaudeService.for_feature("quiz_generate", timeout: 180)

    image_info = ""
    image_paths = []
    if @outline.edit_images.attached?
      Dir.mktmpdir do |dir|
        @outline.edit_images.each_with_index do |img, i|
          path = File.join(dir, img.filename.to_s)
          File.open(path, "wb") { |f| img.download { |chunk| f.write(chunk) } }
          image_paths << path
          image_info += "  - image_#{i + 1}: #{img.filename} (dùng IMAGE:image_#{i + 1} trong bullet để chèn)\n"
        end

        _do_ai_edit(svc, current_slides, edit_prompt, image_info, image_paths)
        return
      end
    end

    _do_ai_edit(svc, current_slides, edit_prompt, image_info, image_paths)
  end

  def _do_ai_edit(svc, current_slides, edit_prompt, image_info, image_paths)
    image_note = image_info.present? ? "\n\nẢnh đính kèm:\n#{image_info}\nĐể chèn ảnh vào slide, thêm bullet có nội dung: IMAGE:image_1 (hoặc image_2, ...)\n" : ""

    existing_theme = @outline.content&.[](/data-theme='([^']+)'/, 1) || "green"
    slides_text = current_slides.each_with_index.map { |s, _|
      layout = s["layout"] || "bullets"
      lines = case layout
      when "stats"
        (s["items"] || []).map { |it| "- #{it['value']} :: #{it['label']}" }
      when "chart"
        (s["items"] || []).map { |it| "- #{it['value']} :: #{it['label']}" }
      when "two-col"
        arr = []
        arr << "- HEADERS: #{(s['headers'] || []).join(' | ')}"
        (s["col1"] || []).each { |c| arr << "- COL1: #{c}" }
        (s["col2"] || []).each { |c| arr << "- COL2: #{c}" }
        arr
      when "timeline", "pillars", "roles", "agenda"
        (s["items"] || []).map { |it| "- #{it.is_a?(Hash) ? it.values.join(' :: ') : it}" }
      else
        (s["bullets"] || []).map { |b| "- #{b.is_a?(Hash) ? b.values.join(' :: ') : b}" }
      end
      body = lines.join("\n")
      style_str = (s["style"] || {}).map { |k, v| "#{k}=#{v}" }.join(", ")
      style_line = style_str.present? ? "\nSTYLE: #{style_str}" : ""
      subtitle_line = s["subtitle"].present? ? "\nSUBTITLE: #{s['subtitle']}" : ""
      footer_line = s["footer"].present? ? "\nFOOTER: #{s['footer']}" : ""
      "---SLIDE---\nTITLE: #{s['title']}#{subtitle_line}\nLAYOUT: #{layout}\nBODY:\n#{body}#{style_line}#{footer_line}\nNOTE: #{s['note']}\n---END---"
    }.join("\n\n")

    prompt = <<~PROMPT
      Đây là nội dung slide hiện tại:

      THEME: #{existing_theme}
      #{slides_text}

      Yêu cầu chỉnh sửa từ người dùng: #{edit_prompt}#{image_note}

      Hãy chỉnh sửa slide theo yêu cầu và trả về ĐÚNG FORMAT sau (bắt buộc dùng ---SLIDE--- và ---END---):
      THEME: #{existing_theme}
      ---SLIDE---
      TITLE: ...
      SUBTITLE: ... (mô tả ngắn 1 câu)
      LAYOUT: ...
      BODY:
      - ...
      STYLE: key=value, key=value (tùy chọn: category, decorations, separator, bg, card_style)
      FOOTER: ... (tùy chọn)
      NOTE: ...
      ---END---

      QUAN TRỌNG:
      - Nếu người dùng yêu cầu thay đổi THIẾT KẾ, dùng dòng STYLE.
      - Mỗi content slide NÊN có SUBTITLE và STYLE: category=... (nhãn ngắn).
    PROMPT

    result = svc.call(system_prompt: slide_system, user_prompt: prompt, max_tokens: 8000)
    slides = parse_slides(result)
    html   = slides_to_html(slides)
    pptx_path = generate_pptx(slides, image_paths: image_paths)
    @outline.update!(content: html, slide_json: slides.to_json, status: :done)
    attach_pptx(pptx_path) if pptx_path
    @outline.workspace.active_subscription&.deduct_credits!(1)
  end

  private

  # ── AI prompts ──────────────────────────────────────────────────────────────

  def slide_system
    <<~SYS.squish
      Bạn là chuyên gia thiết kế slide thuyết trình doanh nghiệp cấp cao (McKinsey, BCG).
      Trả lời bằng tiếng Việt. Chỉ xuất đúng format, không thêm gì khác.

      QUY TẮC VÀNG:
      1. COVER: TITLE = TÊN DỰ ÁN (1-3 từ). Mô tả đặt vào SUBTITLE. KHÔNG nhồi nhét số liệu vào cover.
      2. NỘI DUNG PHẢI SÂU VÀ CỤ THỂ — mỗi bullet/item phải có thông tin thực sự hữu ích, có ngữ cảnh, có số liệu kèm nguồn khi có thể.
      3. TITLE content slide: 1 câu insight (tối đa 45 ký tự), viết thường tự nhiên. KHÔNG dài hơn 1 dòng.
      4. Mỗi slide PHẢI có STYLE: category=... (nhãn 2-4 từ phía trên title).
      5. KHÔNG lặp layout — xen kẽ đa dạng: stats, pillars, two-col, timeline, roles, chart.
      6. TUYỆT ĐỐI KHÔNG dùng emoji (🌱💰📈❌). Slide chuyên nghiệp không có emoji.
      7. FOOTER dùng cho nguồn dữ liệu (VD: "Nguồn: Nielsen Vietnam 2023") hoặc disclaimer.
      8. Nội dung phải tự nhiên, có chiều sâu — KHÔNG viết kiểu liệt kê khô khan.
      9. CHỈ TẠO ĐÚNG 8 SLIDE (cover + 6 content + summary). Ít slide nhưng mỗi slide phải chất lượng cao, đậm đặc thông tin.
      10. TIÊU ĐỀ bullet/item: tối đa 25 ký tự (5-6 từ). Viết ngắn gọn, súc tích. Phần giải thích đặt vào desc sau "::".
    SYS
  end

  def slide_user
    <<~PROMPT
      Tạo bộ slide thuyết trình CHUYÊN NGHIỆP, TRỰC QUAN, PHONG PHÚ cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      ĐẦU TIÊN, chọn THEME MÀU phù hợp nhất cho chủ đề (dòng đầu tiên trước ---SLIDE---):
      THEME: [tên theme]

      Các theme có sẵn:
      - green: xanh lá (môi trường, nông nghiệp, sức khỏe, thực phẩm, bền vững)
      - blue: xanh dương (công nghệ, doanh nghiệp, tài chính, giáo dục)
      - purple: tím (sáng tạo, nghệ thuật, thời trang, marketing)
      - red: đỏ cam (startup, năng lượng, thể thao, y tế khẩn cấp)
      - teal: xanh ngọc (du lịch, hospitality, spa, wellness)
      - amber: vàng nâu (xây dựng, bất động sản, F&B, truyền thống)
      - slate: xám đậm (luật, tư vấn, corporate, cao cấp)
      - earth: nâu đất (kiến trúc, nội thất, handmade, truyền thống Việt)
      - coral: san hô (thời trang nữ, beauty, lifestyle, sự kiện)
      - ocean: xanh đại dương (hàng hải, logistics, thuỷ sản, du lịch biển)
      - berry: tím hồng (mỹ phẩm, wedding, luxury, thời trang cao cấp)
      - midnight: xanh đêm (fintech, blockchain, AI/ML, nghiên cứu khoa học)

      Tạo ĐÚNG 8 slide (1 cover + 6 content + 1 summary), mỗi slide theo đúng format này:

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
        Stats hiển thị bên TRÁI (dark cards), chart bên PHẢI.
        Ví dụ:
        - 50K+ :: Người dùng hoạt động hàng tháng (MAU)
        - 200K :: USD/tháng · Tổng giá trị giao dịch (GMV)
        CHART_LABEL: Người dùng hoạt động hàng tháng (MAU, nghìn)
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
        Ví dụ:
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
      - bg=dark|light           → Nền tối hoặc sáng. Mặc định: light
      - chart_type=line|bar     → Loại biểu đồ (chỉ cho LAYOUT: chart). Mặc định: bar
      - icon=TÊN_ICON           → Icon cho cover/summary. Chọn 1 trong: search, store, check, clock, person, people, rocket, code, chart, money, percent, megaphone, crown, lightbulb, shield, star, heart, globe, target, handshake, leaf, phone, truck
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
      - Bullets dùng format "Tiêu đề :: Mô tả chi tiết" — phần mô tả 1-2 câu ngắn gọn, có ngữ cảnh
      - Số liệu phải CỤ THỂ và có nguồn nếu có trong prompt
      - KHÔNG dùng emoji bất kỳ đâu trong nội dung
      - TITLE content slide: viết thường tự nhiên, truyền tải insight chính

      ═══ QUY TẮC LAYOUT ═══
      - KHÔNG dùng bullets cho 3 slide liên tiếp — xen kẽ đa dạng
      - Mỗi item trong pillars/roles: ít nhất 3 bullets sau "::"
      - STYLE: category=... BẮT BUỘC cho mọi content slide
      - Dùng FOOTER cho nguồn dữ liệu (VD: "Nguồn: Nielsen Vietnam 2023, Statista")
      - Dùng FOOTER cho disclaimer khi cần (VD: "* Thông tin minh hoạ — thay bằng dữ liệu thật trước khi gửi")
      - Slide cuối nên là summary/CTA ngắn gọn

      ═══ QUY TẮC SUMMARY (slide cuối) ═══
      - TITLE = câu call-to-action hoặc kết luận mạnh, KHÔNG dùng emoji
      - Bullets: CTA, thông tin liên hệ, hoặc next steps. KHÔNG emoji.
      - STYLE BẮT BUỘC: bg=dark, summary_style, icon
        + summary_style: chọn phù hợp (cta cho pitch/đề xuất, quote cho bài giảng/truyền cảm hứng, minimal cho báo cáo/nội bộ)
        + icon: chọn giống hoặc liên quan icon cover
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
    @slide_theme = text[/THEME:\s*(\w+)/i, 1]&.strip&.downcase || "blue"

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
        chart_section = body[/CHART_ITEMS:\n(.*?)(?:\nSTYLE:|\nFOOTER:|\nCHART_LABEL:|\z)/m, 1]
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
            { "value" => parts[0].to_i, "label" => parts[1] || "" }
          end
          slide["chart_label"] = chart_label_line || ""
        end
        slide["bullets"] = stat_lines
      when "chart"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0].to_i, "label" => parts[1] || "" }
        end
        slide["bullets"] = lines
      when "donut"
        center_line = lines.find { |l| l.start_with?("CENTER:") }
        data_lines = lines.reject { |l| l.start_with?("CENTER:") }
        slide["items"] = data_lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          { "value" => parts[0].to_i, "label" => parts[1] || "", "detail" => parts[2] || "" }
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
          { "step" => parts[0], "desc" => parts[1] || "" }
        end
        slide["bullets"] = lines
      when "pillars"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          bullets = (parts[1] || "").split("|").map(&:strip).reject(&:empty?)
          { "title" => parts[0], "bullets" => bullets }
        end
        slide["bullets"] = lines
      when "agenda"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          { "num" => parts[0], "title" => parts[1] || "", "desc" => parts[2] || "" }
        end
        slide["bullets"] = lines
      when "roles"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 3).map(&:strip)
          bullets = (parts[2] || "").split("|").map(&:strip).reject(&:empty?)
          { "role" => parts[0], "type" => parts[1] || "", "bullets" => bullets }
        end
        slide["bullets"] = lines
      when "okr"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          krs = (parts[1] || "").split("|").map(&:strip).reject(&:empty?)
          { "objective" => parts[0], "krs" => krs }
        end
        slide["bullets"] = lines
      when "principles"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "title" => parts[0], "desc" => parts[1] || "" }
        end
        slide["bullets"] = lines
      else
        has_desc = lines.any? { |l| l.include?("::") }
        if has_desc
          slide["bullet_items"] = lines.map do |l|
            parts = l.split("::", 2).map(&:strip)
            { "title" => parts[0], "desc" => parts[1] || "" }
          end
        end
        slide["bullets"] = lines.map { |l| l.split("::", 2).first.strip }
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

  def generate_pptx(slides, image_paths: [])
    return nil if slides.empty?
    return nil unless File.exist?(PPTX_SCRIPT)

    out_path = Rails.root.join("tmp", "slide_#{@outline.id}_#{Time.now.to_i}.pptx").to_s
    theme = @slide_theme || "blue"
    require "open3"
    args = ["python3", PPTX_SCRIPT, slides.to_json, out_path, theme]
    args += ["--images", image_paths.compact.join(",")] if image_paths.compact.any?
    stdout, stderr, status = Open3.capture3(*args)
    Rails.logger.error "[PPTX] #{stderr}" if stderr.present?
    status.success? && File.exist?(out_path) ? out_path : nil
  rescue => e
    Rails.logger.error "[PPTX] #{e.message}"
    nil
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
