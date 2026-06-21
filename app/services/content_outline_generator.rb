class ContentOutlineGenerator
  PPTX_SCRIPT = Rails.root.join("scripts", "generate_pptx.py").to_s

  def self.call(outline)
    new(outline).call
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
  end

  private

  # ── AI prompts ──────────────────────────────────────────────────────────────

  def slide_system
    "Bạn là chuyên gia thiết kế slide thuyết trình doanh nghiệp chuyên nghiệp. Trả lời bằng tiếng Việt. Chỉ xuất đúng format được yêu cầu, không thêm văn bản khác."
  end

  def slide_user
    <<~PROMPT
      Tạo bộ slide thuyết trình CHUYÊN NGHIỆP, TRỰC QUAN, PHONG PHÚ cho chủ đề: "#{@outline.title}"#{@outline.subject.present? ? " (#{@outline.subject})" : ""}.
      Yêu cầu bổ sung: #{@outline.prompt_input.presence || 'Không có'}

      Tạo 8–10 slide, mỗi slide theo đúng format này:

      ---SLIDE---
      TITLE: Tiêu đề slide (IN HOA, súc tích)
      LAYOUT: [tên layout]
      BODY:
      [nội dung theo format của layout đã chọn]
      NOTE: Ghi chú 1-2 câu cho người trình bày (câu hỏi tương tác hoặc insight bổ sung)
      ---END---

      ═══════════════════════════════════════════
      CÁC LOẠI LAYOUT — chọn layout PHÙ HỢP NHẤT với nội dung:
      ═══════════════════════════════════════════

      LAYOUT: bullets
        Khi nào dùng: 3–5 điểm chính, mỗi điểm độc lập
        Format: mỗi dòng "- nội dung CỤ THỂ, có số liệu/ví dụ"
        Ví dụ:
        - 87% học sinh cải thiện điểm sau 4 tuần áp dụng phương pháp mới
        - Giảm thời gian chuẩn bị bài 40% nhờ AI-assisted planning

      LAYOUT: stats
        Khi nào dùng: 3–4 con số/chỉ số quan trọng (KPI, kết quả đo lường được)
        Format: mỗi dòng "- GIÁ_TRỊ :: MÔ_TẢ_NGẮN"
        Ví dụ:
        - 87% :: Tỷ lệ học sinh đạt mục tiêu
        - 3.2x :: Cải thiện điểm số trung bình
        - 12 tuần :: Thời gian hoàn thành khóa học
        - 92% :: Mức độ hài lòng phụ huynh

      LAYOUT: chart
        Khi nào dùng: so sánh theo thời gian, tiến độ tăng trưởng, phân bổ theo nhóm
        Format: mỗi dòng "- SỐ_NGUYÊN_0_TO_100 :: NHÃN" (tối đa 5 cột)
        Ví dụ:
        - 45 :: Quý 1
        - 62 :: Quý 2
        - 78 :: Quý 3
        - 91 :: Quý 4

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
        Khi nào dùng: mô tả 2–3 vai trò/chức năng/bộ phận trong tổ chức
        Format: mỗi dòng "- TÊN VAI TRÒ :: Phạm vi/Loại :: trách nhiệm 1 | trách nhiệm 2 | trách nhiệm 3"
        Ví dụ:
        - GIÁO VIÊN :: Người truyền đạt tri thức :: Soạn bài theo chuẩn | Tương tác với học sinh | Đánh giá kết quả
        - MENTOR :: Người đồng hành :: Hỗ trợ cá nhân hóa | Theo dõi tiến độ | Giải đáp thắc mắc
        - ADMIN :: Vận hành hệ thống :: Quản lý nền tảng | Báo cáo dữ liệu | Hỗ trợ kỹ thuật

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
      - Có nhiều số liệu, KPI → stats hoặc chart
      - Có nhiều trụ cột/chiến lược song song → pillars
      - Có nhiều vai trò, bộ phận → roles
      - Có mục tiêu, key results → okr
      - Có quy trình tuần tự → timeline
      - Có 2 phía so sánh → two-col
      - Slide mở đầu overview → agenda
      - Giá trị, nguyên tắc → principles
      - Nội dung tổng quát → bullets

      TIÊU CHUẨN CHẤT LƯỢNG:
      - Nội dung PHẢI CỤ THỂ: có con số, %, tỉ lệ, ví dụ thực tế (không chung chung)
      - KHÔNG dùng bullets cho 3 slide liên tiếp — phải xen kẽ layout đa dạng
      - Mỗi item trong pillars/roles phải có ít nhất 3 bullets sau "::"
      - NOTE phải là câu hỏi tương tác hay insight bổ sung thực sự có giá trị
      - Slide đầu tiên nên là cover/giới thiệu chủ đề, slide cuối nên là tóm tắt hoặc CTA
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
    raw = text.scan(/---SLIDE---(.*?)---END---/m).flatten
    return [] if raw.empty?

    raw.map do |s|
      title  = s[/TITLE:\s*(.+)/, 1]&.strip || "Slide"
      layout = s[/LAYOUT:\s*(\S+)/, 1]&.strip&.downcase || "bullets"
      body   = s[/BODY:\n(.*?)(?:\nNOTE:|\z)/m, 1]&.strip || ""
      note   = s[/NOTE:\s*(.+)/, 1]&.strip || ""
      lines  = body.lines.map { |l| l.sub(/^-\s*/, "").strip }.reject(&:empty?)

      slide = { "title" => title, "layout" => layout, "note" => note }

      case layout
      when "stats"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0], "label" => parts[1] || "" }
        end
        slide["bullets"] = lines
      when "chart"
        slide["items"] = lines.map do |l|
          parts = l.split("::", 2).map(&:strip)
          { "value" => parts[0].to_i, "label" => parts[1] || "" }
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
        slide["bullets"] = lines
      end

      slide
    end
  end

  def slides_to_html(slides)
    return "<p>Không thể tạo slide.</p>" if slides.empty?
    "<div id='slide-deck-root' data-slides='#{ERB::Util.html_escape(slides.to_json)}'></div>"
  end

  # ── PPTX generation ─────────────────────────────────────────────────────────

  def generate_pptx(slides)
    return nil if slides.empty?
    return nil unless File.exist?(PPTX_SCRIPT)

    out_path = Rails.root.join("tmp", "slide_#{@outline.id}_#{Time.now.to_i}.pptx").to_s
    require "open3"
    stdout, stderr, status = Open3.capture3(
      "python3", PPTX_SCRIPT, slides.to_json, out_path
    )
    Rails.logger.error "[PPTX] #{stderr}" if stderr.present?
    status.success? && File.exist?(out_path) ? out_path : nil
  rescue => e
    Rails.logger.error "[PPTX] #{e.message}"
    nil
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
