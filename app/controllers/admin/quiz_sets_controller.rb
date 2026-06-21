class Admin::QuizSetsController < Admin::BaseController
  before_action :set_quiz_set, only: [:show, :edit, :update, :destroy, :publish, :unpublish, :results, :attempt_detail, :send_result_email, :ai_evaluate_attempt, :ai_evaluate_results, :update_ai_evaluation, :send_ai_evaluation_email]

  def index
    @quiz_sets = current_workspace.quiz_sets.order(created_at: :desc)
  end

  def show
    @questions = @quiz_set.quiz_questions.includes(:quiz_options)
  end

  def new
    @quiz_set = current_workspace.quiz_sets.build
  end

  def create
    @quiz_set = current_workspace.quiz_sets.build(quiz_set_params)
    @quiz_set.user = current_user
    if @quiz_set.save
      redirect_to edit_quiz_set_path(@quiz_set), notice: t("quiz.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @questions = @quiz_set.quiz_questions.includes(:quiz_options)
  end

  def update
    if @quiz_set.update(quiz_set_params)
      redirect_to edit_quiz_set_path(@quiz_set), notice: t("quiz.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quiz_set.destroy
    redirect_to quiz_sets_path, notice: t("quiz.deleted")
  end

  def publish
    @quiz_set.update!(status: :published)
    redirect_to edit_quiz_set_path(@quiz_set), notice: t("quiz.published")
  end

  def unpublish
    @quiz_set.update!(status: :draft)
    redirect_to edit_quiz_set_path(@quiz_set), notice: t("quiz.unpublished")
  end

  def results
    @pagy, @attempts = pagy(
      @quiz_set.quiz_attempts.where.not(submitted_at: nil).order(submitted_at: :desc),
      items: 20
    )
    @all_attempts = @quiz_set.quiz_attempts.where.not(submitted_at: nil)
  end

  def attempt_detail
    @attempt   = @quiz_set.quiz_attempts.find(params[:attempt_id])
    @questions = @quiz_set.quiz_questions.includes(:quiz_options)
    @answers_by_q = @attempt.quiz_attempt_answers.includes(:quiz_option).group_by(&:quiz_question_id)
  end

  def ai_evaluate_attempt
    attempt   = @quiz_set.quiz_attempts.find(params[:attempt_id])

    # Return cached result if already evaluated
    if attempt.ai_evaluation.present? && !params[:force].present?
      return render json: { html: attempt.ai_evaluation, cached: true, evaluated_at: attempt.ai_evaluated_at }
    end

    return unless require_credits!(2)

    questions    = @quiz_set.quiz_questions.includes(:quiz_options)
    answers_by_q = attempt.quiz_attempt_answers.includes(:quiz_option).group_by(&:quiz_question_id)

    correct_qs = []
    wrong_qs   = []
    questions.each_with_index do |q, i|
      my      = answers_by_q[q.id] || []
      correct = my.any?(&:is_correct?)
      next if q.short_answer?
      selected     = my.map { |a| plain_text(a.quiz_option&.option_text) }.compact.join(", ").presence || "không chọn"
      correct_opts = q.quiz_options.select(&:is_correct?).map { |o| plain_text(o.option_text) }.join(", ")
      q_text       = plain_text(q.question_text)
      entry = "Câu #{i + 1}: #{q_text}\n   Đáp án đúng: #{correct_opts}\n   Học sinh chọn: #{selected}"
      correct ? correct_qs << entry : wrong_qs << entry
    end

    prompt = <<~PROMPT
      Bạn là một trợ lý đánh giá kết quả bài kiểm tra.

      **Người làm bài:** #{attempt.participant_name}
      **Bài kiểm tra:** #{@quiz_set.title}
      **Kết quả:** #{attempt.score_pct}% — #{attempt.earned_points}/#{attempt.total_points} điểm — #{attempt.passed? ? "ĐẠT" : "CHƯA ĐẠT"}
      **Số câu đúng:** #{correct_qs.size}/#{questions.count}

      **Câu trả lời đúng (#{correct_qs.size} câu):**
      #{correct_qs.any? ? correct_qs.join("\n\n") : "Không có câu đúng nào."}

      **Câu trả lời sai (#{wrong_qs.size} câu):**
      #{wrong_qs.any? ? wrong_qs.join("\n\n") : "Tất cả đều đúng."}

      Hãy viết nhận xét cá nhân hoá cho #{attempt.participant_name}, bằng tiếng Việt. Trình bày theo 3 phần:

      ## Điểm mạnh
      Những kiến thức/kỹ năng đã nắm vững, dựa trên các câu đúng. Cụ thể, không chung chung.

      ## Cần cải thiện
      Phân tích các lỗi sai: đang hiểu sai ở đâu, lỗi kiến thức hay lỗi suy luận? Nêu rõ chủ đề/kỹ năng còn yếu.

      ## Gợi ý
      2-3 hành động cụ thể để cải thiện. Tránh lời khuyên chung — nói rõ ôn gì, theo cách nào.

      Viết thành đoạn văn tự nhiên, thân thiện, trung lập. Không nhắc đến vai trò "thầy/cô giáo", "giáo viên" — chỉ viết từ góc độ phân tích khách quan hướng đến người làm bài.

      **QUAN TRỌNG**: Mô tả công thức/ký hiệu toán học bằng lời thay vì LaTeX. Ví dụ: "vector u bằng (3; -9)" thay vì "$\vec{u} = (3; -9)$".
    PROMPT

    svc    = ClaudeService.for_feature("quiz_eval_student", timeout: 120)
    result = svc.call(
      system_prompt: "Bạn là trợ lý đánh giá bài kiểm tra, viết nhận xét tự nhiên bằng tiếng Việt với markdown. Không dùng vai trò thầy/cô. Không dùng ký hiệu LaTeX.",
      user_prompt:   prompt,
      max_tokens:    1200
    )

    html = markdown_to_html(result)
    current_workspace.active_subscription.deduct_credits!(2)
    attempt.update_columns(ai_evaluation: html, ai_evaluated_at: Time.current)

    render json: { html: html, cached: false, evaluated_at: Time.current }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def ai_evaluate_results
    attempts  = @quiz_set.quiz_attempts.where.not(submitted_at: nil).includes(quiz_attempt_answers: :quiz_option)
    questions = @quiz_set.quiz_questions.includes(:quiz_options)

    return render json: { error: "Chưa có bài nộp nào." }, status: :unprocessable_entity if attempts.empty?

    # Return cached result unless force refresh
    if @quiz_set.ai_class_evaluation.present? && !params[:force].present?
      return render json: { html: @quiz_set.ai_class_evaluation, cached: true, evaluated_at: @quiz_set.ai_class_evaluated_at }
    end

    return unless require_credits!(3)

    avg       = attempts.sum(&:score_pct).to_f / attempts.count
    passed    = attempts.select(&:passed?).count
    pass_rate = (passed * 100.0 / attempts.count).round

    q_stats = questions.map.with_index(1) do |q, i|
      answers_for_q = attempts.flat_map { |a| a.quiz_attempt_answers.select { |ans| ans.quiz_question_id == q.id } }
      correct_count = answers_for_q.count(&:is_correct?)
      total = attempts.count
      rate  = total > 0 ? (correct_count * 100 / total) : 0
      "Câu #{i}: #{plain_text(q.question_text)} — #{rate}% trả lời đúng (#{correct_count}/#{total})"
    end.join("\n")

    prompt = <<~PROMPT
      Bạn là chuyên gia phân tích kết quả đánh giá năng lực.

      **Bài kiểm tra:** #{@quiz_set.title}
      **Số người tham gia:** #{attempts.count}
      **Điểm trung bình:** #{avg.round(1)}%
      **Tỷ lệ đạt:** #{pass_rate}% (#{passed}/#{attempts.count} người)

      **Thống kê từng câu:**
      #{q_stats}

      Viết phân tích tổng quan ngắn gọn, súc tích bằng tiếng Việt theo 3 phần:

      ## Tổng quan
      Nhận xét chung về kết quả. Đánh giá mức độ nắm bài tổng thể, so sánh với ngưỡng đạt.

      ## Điểm mạnh & điểm yếu
      Nêu rõ các câu/chủ đề được nắm tốt (tỷ lệ đúng cao) và các câu/chủ đề còn yếu (tỷ lệ đúng thấp). Phân tích nguyên nhân có thể.

      ## Đề xuất cải thiện
      3-4 hành động cụ thể để cải thiện chất lượng ôn tập/đánh giá cho nhóm này.

      Viết tự nhiên, khách quan, không dùng cụm "thầy/cô giáo". Không dùng ký hiệu LaTeX — mô tả toán học bằng lời.
    PROMPT

    svc    = ClaudeService.for_feature("quiz_eval_class", timeout: 120)
    result = svc.call(
      system_prompt: "Bạn là chuyên gia phân tích kết quả kiểm tra. Trả lời bằng tiếng Việt, dùng markdown. Không dùng LaTeX.",
      user_prompt:   prompt,
      max_tokens:    1200
    )
    html = markdown_to_html(result)
    current_workspace.active_subscription.deduct_credits!(3)
    @quiz_set.update_columns(ai_class_evaluation: html, ai_class_evaluated_at: Time.current)
    render json: { html: html, cached: false, evaluated_at: Time.current }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def send_result_email
    attempt = @quiz_set.quiz_attempts.find(params[:attempt_id])
    QuizResultMailer.result_email(attempt, @quiz_set).deliver_later
    render json: { success: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /admin/quiz_sets/:id/ai_generate
  def ai_generate
    request.format = :json
    @quiz_set = current_workspace.quiz_sets.find(params[:id])
    return unless require_credits!(5)

    uploaded = params[:file]
    unless uploaded
      return render json: { error: t("quiz.no_file") }, status: :unprocessable_entity
    end

    content = extract_text_from_upload(uploaded)
    if content.blank?
      return render json: { error: t("quiz.extract_failed") }, status: :unprocessable_entity
    end

    questions_count = params[:questions_count].to_i
    auto_mode = questions_count <= 0
    questions_count = questions_count.clamp(3, 50) unless auto_mode
    custom_prompt = params[:custom_prompt].to_s.strip.presence
    result = call_ai_generate(content, auto_mode ? nil : questions_count, custom_prompt)

    if result[:error]
      return render json: { error: result[:error] }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      current_workspace.active_subscription.deduct_credits!(5)
      @quiz_set.update!(source_type: :ai_generated)
      result[:questions].each_with_index do |q, idx|
        question = @quiz_set.quiz_questions.create!(
          question_text: q[:question],
          question_type: :multiple_choice,
          explanation:   q[:explanation],
          position:      @quiz_set.quiz_questions.count + idx
        )
        q[:options].each_with_index do |opt, oi|
          question.quiz_options.create!(
            option_text: opt[:text],
            is_correct:  opt[:correct],
            position:    oi
          )
        end
      end
    end

    render json: { success: true, redirect: edit_quiz_set_path(@quiz_set) }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update_ai_evaluation
    attempt = @quiz_set.quiz_attempts.find(params[:attempt_id])
    html    = params[:html].to_s.strip
    return render json: { error: "Nội dung trống" }, status: :unprocessable_entity if html.blank?
    attempt.update_columns(ai_evaluation: html, ai_evaluated_at: Time.current)
    render json: { ok: true }
  end

  def send_ai_evaluation_email
    attempt = @quiz_set.quiz_attempts.find(params[:attempt_id])
    return render json: { error: "Chưa có đánh giá AI" }, status: :unprocessable_entity if attempt.ai_evaluation.blank?
    QuizResultMailer.ai_evaluation_email(attempt, @quiz_set).deliver_later
    render json: { success: true }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_quiz_set
    @quiz_set = current_workspace.quiz_sets.find(params[:id])
  end

  def plain_text(html)
    return "" if html.blank?
    # Decode HTML entities, strip tags — keeps LaTeX $ notation intact
    ActionController::Base.helpers.strip_tags(html.to_s).gsub(/\s+/, " ").strip
  end

  def markdown_to_html(text)
    # Escape HTML first
    text = ERB::Util.html_escape(text)
    # H1 → title
    text = text.gsub(/^# (.+)$/) { "<h1 style='font-size:16px;font-weight:800;color:#0f172a;margin:0 0 6px;line-height:1.4'>#{$1}</h1>" }
    # H2 → section heading with colored left border block
    section_colors = { 0 => "#10b981", 1 => "#f59e0b", 2 => "#6366f1", 3 => "#3b82f6" }
    section_idx    = -1
    text = text.gsub(/^## (.+)$/) do
      section_idx += 1
      color = section_colors[section_idx % 4]
      "<div style='display:flex;align-items:center;gap:8px;margin:20px 0 10px'><div style='width:4px;height:20px;border-radius:2px;background:#{color};flex-shrink:0'></div><h2 style='font-size:14px;font-weight:800;color:#1e293b;margin:0'>#{$1}</h2></div>"
    end
    # H3 → smaller heading
    text = text.gsub(/^### (.+)$/) { "<h3 style='font-size:13px;font-weight:700;color:#334155;margin:14px 0 6px'>#{$1}</h3>" }
    # Horizontal rule → divider
    text = text.gsub(/^---+$/, "<hr style='border:none;border-top:1px solid #e2e8f0;margin:16px 0'>")
    # Bold
    text = text.gsub(/\*\*(.+?)\*\*/, '<strong style="color:#0f172a">\1</strong>')
    # Italic
    text = text.gsub(/\*(.+?)\*/, '<em>\1</em>')
    # Bullet list items
    text = text.gsub(/^[-•] (.+)$/, '<li style="margin:4px 0;color:#334155">\1</li>')
    # Numbered list items
    text = text.gsub(/^(\d+)\. (.+)$/, '<li style="margin:4px 0;color:#334155">\2</li>')
    # Wrap consecutive <li> in <ul>
    text = text.gsub(/(<li[^>]*>.*?<\/li>(\s*<li[^>]*>.*?<\/li>)*)/m) do
      "<ul style='margin:6px 0 8px 16px;padding:0;list-style:disc'>#{$1}</ul>"
    end
    # Blank lines → paragraph breaks
    text = text.gsub(/\n{2,}/, "</p><p style='margin:6px 0;color:#475569;line-height:1.65;font-size:13px'>")
    text = text.gsub(/\n/, "<br>")
    "<p style='margin:0 0 6px;color:#475569;line-height:1.65;font-size:13px'>#{text}</p>"
  end

  def quiz_set_params
    params.require(:quiz_set).permit(:title, :description, :allow_retake, :show_answers, :time_limit_minutes, :result_mode, :passing_score)
  end

  def extract_text_from_upload(file)
    ext = File.extname(file.original_filename).downcase
    case ext
    when ".pdf"
      extract_pdf(file)
    when ".docx"
      extract_docx(file)
    when ".doc"
      # Old .doc format: try antiword, otherwise treat as binary text
      extract_doc(file)
    when ".txt"
      file.read.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    when ".png", ".jpg", ".jpeg", ".webp", ".gif"
      extract_image_via_ai(file)
    else
      nil
    end
  end

  def extract_pdf(file)
    require "open3"
    tmp = Tempfile.new(["quiz_upload", ".pdf"])
    tmp.binmode
    tmp.write(file.read)
    tmp.flush
    # Try pdftotext first, fall back to python3 pdfminer if available
    stdout, _stderr, status = Open3.capture3("pdftotext", "-enc", "UTF-8", tmp.path, "-")
    if status.success? && stdout.strip.present?
      tmp.close!
      return stdout.strip
    end
    # Fallback: python3 with pdfminer.six or pypdf
    py_out, _e, py_st = Open3.capture3(
      "python3", "-c",
      "import sys\ntry:\n from pdfminer.high_level import extract_text\n print(extract_text(sys.argv[1]))\nexcept:\n try:\n  from pypdf import PdfReader\n  r=PdfReader(sys.argv[1])\n  print(''.join(p.extract_text() or '' for p in r.pages))\n except: pass",
      tmp.path
    )
    tmp.close!
    py_st.success? && py_out.strip.present? ? py_out.strip : nil
  rescue
    nil
  end

  # Extract text from DOCX/DOC using pure Ruby (no external tools needed).
  # DOCX is a ZIP archive containing word/document.xml with the text content.
  def extract_docx(file)
    require "zip"
    data = file.read
    io = StringIO.new(data)
    Zip::File.open_buffer(io) do |zip|
      entry = zip.find_entry("word/document.xml")
      return nil unless entry
      xml = entry.get_input_stream.read.force_encoding("UTF-8")
      # Strip XML tags, collapse whitespace, preserve paragraph breaks
      xml.gsub(/<w:p[ >]/, "\n<w:p>")
         .gsub(/<[^>]+>/, " ")
         .gsub(/\s{2,}/, " ")
         .gsub(/\n /, "\n")
         .strip
    end
  rescue => e
    # Fallback: try docx2txt if installed
    begin
      require "open3"
      tmp = Tempfile.new(["quiz_upload", ".docx"])
      tmp.binmode; tmp.write(data); tmp.flush
      out, _e, st = Open3.capture3("docx2txt.pl", tmp.path, "-")
      tmp.close!
      st.success? ? out.strip.presence : nil
    rescue
      nil
    end
  end

  def extract_doc(file)
    require "open3"
    data = file.read
    tmp = Tempfile.new(["quiz_upload", ".doc"])
    tmp.binmode; tmp.write(data); tmp.flush
    out, _e, st = Open3.capture3("antiword", tmp.path)
    tmp.close!
    return out.strip if st.success? && out.strip.present?
    # Fallback: strip binary, keep printable ASCII/UTF-8 runs (rough extraction)
    data.force_encoding("binary")
        .scan(/[\x20-\x7E\n\r]{4,}/)
        .join(" ")
        .gsub(/\s+/, " ")
        .strip
        .presence
  rescue
    nil
  end

  def extract_image_via_ai(file)
    { image_base64: Base64.strict_encode64(file.read), mime_type: file.content_type }
  end

  def call_ai_generate(content, count, custom_prompt = nil)
    if content.is_a?(Hash) && content[:image_base64]
      messages = [{
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: content[:mime_type], data: content[:image_base64] } },
          { type: "text", text: quiz_prompt(count, custom_prompt) }
        ]
      }]
      svc = ClaudeService.for_feature("quiz_generate", timeout: 180)
      raw = svc.call(system_prompt: "You are a quiz generator. Always respond with valid JSON only.", messages: messages, max_tokens: 4000)
    else
      user_prompt = "#{quiz_prompt(count, custom_prompt)}\n\n---\n#{content.to_s.truncate(12000)}"
      svc = ClaudeService.for_feature("quiz_generate", timeout: 180)
      raw = svc.call(system_prompt: "You are a quiz generator. Always respond with valid JSON only.", user_prompt: user_prompt, max_tokens: 4000)
    end

    json_str = raw[/\{.*\}/m] || raw[/\[.*\]/m]
    raise "AI did not return valid JSON" if json_str.nil?

    # Try parsing directly; if it fails due to invalid LaTeX backslashes, sanitize and retry
    parsed = begin
      JSON.parse(json_str, symbolize_names: true)
    rescue JSON::ParserError
      JSON.parse(sanitize_latex_json(json_str), symbolize_names: true)
    end

    questions = parsed.is_a?(Array) ? parsed : parsed[:questions]
    raise "No questions found in AI response" if questions.blank?
    { questions: questions }
  rescue JSON::ParserError => e
    { error: "AI trả về JSON không hợp lệ: #{e.message}" }
  rescue => e
    { error: e.message }
  end

  # Fix LaTeX backslashes that are invalid in JSON.
  # JSON only allows: \", \\, \/, \b, \f, \n, \r, \t, \uXXXX
  # LaTeX uses \vec, \frac, \Delta, etc. — these need to be \\vec etc. in JSON.
  def sanitize_latex_json(str)
    # Inside JSON string values, replace \ followed by a letter or { or }
    # that doesn't form a valid JSON escape, with \\.
    # We scan through character by character inside string context.
    result = +""
    i = 0
    in_string = false
    while i < str.length
      ch = str[i]
      if ch == '"' && (i == 0 || str[i - 1] != '\\')
        in_string = !in_string
        result << ch
      elsif in_string && ch == '\\'
        next_ch = str[i + 1]
        if next_ch && %w[" \\ / b f n r t u].include?(next_ch)
          # Valid JSON escape — keep as-is
          result << ch << next_ch
          i += 2
          next
        else
          # Invalid escape (LaTeX command like \vec, \frac) — double the backslash
          result << '\\\\'
        end
      else
        result << ch
      end
      i += 1
    end
    result
  end

  def quiz_prompt(count, custom_prompt = nil)
    count_instruction = count.nil? \
      ? "Extract ALL multiple-choice questions found in the document. Do not invent new ones — only extract what is already there." \
      : "Generate exactly #{count} multiple-choice questions based on the content."

    user_instruction = custom_prompt.present? \
      ? "\n\nAdditional instructions from the user (follow these closely):\n#{custom_prompt}" \
      : ""

    <<~PROMPT
      You are a quiz extractor/generator. #{count_instruction}#{user_instruction}

      Return ONLY valid JSON (no markdown, no explanation), in this exact format:
      {
        "questions": [
          {
            "question": "Question text here",
            "options": [
              {"text": "Option A", "correct": true},
              {"text": "Option B", "correct": false},
              {"text": "Option C", "correct": false},
              {"text": "Option D", "correct": false}
            ],
            "explanation": "Brief explanation of the correct answer"
          }
        ]
      }

      Rules:
      - Each question must have exactly 4 options
      - Exactly 1 option must have "correct": true
      - If extracting from file: preserve the original question wording and options exactly
      - If generating: base questions on the provided content
      - Always follow the user's additional instructions above if provided
      - For mathematical expressions, use LaTeX wrapped in $ signs: e.g. $\\vec{u}$, $x^2 + 5x + 10 > 0$, $\\Delta_a = |\\bar{a} - a|$
      - IMPORTANT: In JSON strings, backslashes must be escaped as \\. Write $\\vec{u}$ not $\vec{u}$, $\\frac{1}{2}$ not $\frac{1}{2}$
    PROMPT
  end
end
