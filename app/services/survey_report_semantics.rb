# SurveyReportSemantics
# Analyzes survey questions + actual response data to deterministically build
# a high-quality report structure. AI is only used for narrative insights.
#
# Usage:
#   builder = SurveyReportSemantics.new(survey, completed_response_ids)
#   structure = builder.build_structure   # → report_structure hash
#   semantics = builder.semantics         # → per-question semantic info
#
class SurveyReportSemantics
  # ── Tool name normalization ──────────────────────────────────────────────
  TOOL_NORMALIZE = {
    /chatgpt|chat\s*gpt|gpt[-\s]?[34o]/i  => "ChatGPT",
    /claude\s*code/i                       => "Claude Code",
    /claude/i                              => "Claude",
    /gemini|bard/i                         => "Gemini",
    /github\s*copilot/i                    => "GitHub Copilot",
    /copilot/i                             => "GitHub Copilot",
    /cursor/i                              => "Cursor",
    /codex/i                               => "Codex",
    /midjourney/i                          => "Midjourney",
    /dall[-\s]?e/i                         => "DALL-E",
    /perplexity/i                          => "Perplexity",
    /bing\s*(ai|chat)?/i                   => "Bing AI",
    /deepseek/i                            => "DeepSeek",
    /antigravity/i                         => "Antigravity",
    /trae/i                                => "Trae",
    /stable\s*diffusion/i                  => "Stable Diffusion",
    /canva/i                               => "Canva AI",
    /notion\s*ai/i                         => "Notion AI",
    /grammarly/i                           => "Grammarly",
    /jasper/i                              => "Jasper",
  }.freeze

  # ── Theme keyword rules ──────────────────────────────────────────────────
  THEME_RULES = [
    { label: "Tổ chức buổi sharing/training",  kws: %w[sharing training chia sẻ đào tạo workshop học tập] },
    { label: "Cung cấp tài khoản AI",           kws: %w[tài khoản account premium trả phí license] },
    { label: "Xây dựng quy trình chuẩn",        kws: %w[quy trình quy chuẩn chuẩn hóa workflow standard hướng dẫn] },
    { label: "Hỗ trợ tài chính",                kws: %w[tài chính financial hỗ trợ budget chi phí] },
    { label: "Nguyên tắc bảo mật",              kws: %w[bảo mật security an toàn data dữ liệu riêng tư] },
    { label: "Tự động hóa quy trình",           kws: %w[tự động automation tự động hóa] },
    { label: "Tạo nội dung / Viết lách",        kws: %w[viết văn content nội dung soạn thảo] },
    { label: "Phân tích & Báo cáo",             kws: %w[phân tích analysis báo cáo report dữ liệu] },
    { label: "Lập trình / Code",                kws: %w[code lập trình debug script] },
    { label: "Tra cứu & Tìm kiếm",             kws: %w[tra cứu tìm kiếm search thông tin] },
    { label: "Dịch thuật",                      kws: %w[dịch translate ngôn ngữ language] },
    { label: "Thiết kế / Hình ảnh",             kws: %w[thiết kế design hình ảnh image] },
    { label: "Tóm tắt tài liệu",               kws: %w[tóm tắt summary tài liệu document] },
    { label: "Lên kế hoạch",                    kws: %w[kế hoạch plan lịch schedule] },
  ].freeze

  # ── PCT distribution buckets ──────────────────────────────────────────────
  PCT_BUCKETS = [
    ["<40%",  0,   39],
    ["40–49%", 40,  49],
    ["50–59%", 50,  59],
    ["60–69%", 60,  69],
    ["70–79%", 70,  79],
    ["80–89%", 80,  89],
    ["≥90%",  90, 100],
  ].freeze

  attr_reader :semantics

  def initialize(survey, completed_response_ids = nil)
    @survey               = survey
    @questions            = survey.questions.includes(:question_options).order(:position)
    @completed_ids        = completed_response_ids ||
                            survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    @opt_label            = @questions.flat_map(&:question_options)
                                      .each_with_object({}) { |o, h| h[o.id.to_i] = o.label }
    @total_responses      = @completed_ids.size
    @semantics            = {}
  end

  # ── Public: build full report structure ─────────────────────────────────
  def build_structure
    detect_all_semantics!
    sections = build_sections
    kpis     = build_kpis
    { "kpis" => kpis, "sections" => sections, "ai_insights" => [], "_auto_built" => true }
  end

  # ── Public: catalog for the AI section-planner (id, role, chart, title) ─────
  # Excludes questions that produce no chart (empty / plain short text).
  def chartable_catalog
    detect_all_semantics! if @semantics.empty?
    @questions.filter_map do |q|
      sem = @semantics[q.id]
      next if sem.nil? || sem[:chart_type].nil? || sem[:role].in?(%i[empty text unknown])
      { "id" => q.id, "role" => sem[:role].to_s, "chart" => sem[:chart_type], "title" => q.title.to_s.truncate(70) }
    end
  end

  # ── Public: rebuild sections from an AI-proposed grouping ───────────────────
  # grouping: [{ "title" => "...", "question_ids" => [..] }, ...] (ordered).
  # Reuses per-question chart types + auto-inserts cross-tab cards. Returns nil
  # if nothing valid could be built (caller falls back to deterministic build).
  def build_sections_from_grouping(grouping)
    detect_all_semantics! if @semantics.empty?
    return nil unless grouping.is_a?(Array) && grouping.any?
    group_q = (qs_for(:grouping).presence ||
               ReportAnalytics.grouping_questions(@questions)).reject { |q| @semantics[q.id]&.dig(:role) == :frequency }.first
    used = Set.new
    sections = grouping.each_with_index.filter_map do |sec, idx|
      qs = Array(sec["question_ids"]).map(&:to_i).uniq
              .map { |id| @questions.find { |q| q.id == id } }.compact
              .reject { |q| used.include?(q.id) }
      cards = []; pct_in = []; num_in = []
      qs.each do |q|
        sem = @semantics[q.id]
        next if sem.nil? || sem[:chart_type].nil? || sem[:role].in?(%i[empty text unknown])
        used << q.id
        span = %w[distribution_bar theme_bar quotes rating_bar nps_bar].include?(sem[:chart_type]) ? 12 : 6
        cards << mk_card(q, sem[:chart_type], sem[:processing], span)
        pct_in << q if sem[:role] == :pct
        num_in << q if sem[:role] == :numeric
      end
      cards << cross_tab_card(group_q, pct_in, "parse_percent") if group_q && pct_in.any?
      cards << cross_tab_card(group_q, num_in, nil)             if group_q && num_in.any?
      next if cards.empty?
      { "id" => "s#{idx + 1}", "title" => sec["title"].to_s.strip.presence || "Phân tích", "layout" => "grid-2", "cards" => cards }
    end
    sections.presence
  end

  # ── Public: data summary for AI (used to generate insights) ─────────────
  def data_summary_for_ai
    detect_all_semantics! if @semantics.empty?
    lines = []
    @questions.each_with_index do |q, i|
      sem  = @semantics[q.id] || {}
      data = sem[:data_summary]
      next unless data.present?
      lines << "Q#{i+1} (ID #{q.id}) [#{q.question_type}] #{q.title.truncate(70)}\n  #{data}"
    end
    lines.join("\n\n")
  end

  # ── Public: tool normalization (shared with concern) ────────────────────
  def self.normalize_tool(text)
    text = text.to_s.strip
    match = TOOL_NORMALIZE.find { |pat, _| text.match?(pat) }
    return match.last if match
    text.split(/\s+/).first(3).map(&:capitalize).join(" ")
  end

  # ── Public: JSONB option_ids matcher — delegates to the shared core ─────
  def self.option_match(option_id)
    ReportAnalytics.option_match(option_id)
  end

  # ── Public: parse % from text ─────────────────────────────────────────
  def self.parse_pct(text)
    n = text.to_s.gsub(/[~≈≤≥\s%]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f
    (n && n > 0 && n <= 100) ? n : nil
  end

  # ── Public: pct distribution ─────────────────────────────────────────
  def self.build_pct_distribution(vals)
    PCT_BUCKETS.filter_map do |label, lo, hi|
      count = lo == 0 ? vals.count { |v| v < 40 } : vals.count { |v| v >= lo && v <= hi }
      count > 0 ? { label: label, count: count, pct: vals.size > 0 ? (count.to_f / vals.size * 100).round(1) : 0 } : nil
    end
  end

  # ── Public: theme extraction ─────────────────────────────────────────
  def self.extract_themes(texts, total)
    THEME_RULES.filter_map do |rule|
      count = texts.count { |t| rule[:kws].any? { |kw| t.downcase.include?(kw) } }
      count > 0 ? { label: rule[:label], count: count,
                    pct: total > 0 ? (count.to_f / total * 100).round(1) : 0 } : nil
    end.sort_by { |t| -t[:count] }
  end

  # ── Public: tool aggregation ─────────────────────────────────────────
  def self.aggregate_tools(texts, total)
    tc = Hash.new(0)
    texts.each do |raw|
      raw.to_s.split(/[,，、;；\n\/＋\+]+/).map(&:strip).reject(&:blank?).each do |part|
        next if part.split(/\s+/).size > 5  # skip sentences, only short tool-name-like fragments
        tc[normalize_tool(part)] += 1 if part.length > 1
      end
    end
    tc.sort_by { |_, c| -c }.first(15).map do |name, count|
      { label: name, count: count, pct: total > 0 ? (count.to_f / total * 100).round(1) : 0 }
    end
  end

  private

  # ── Detect semantic roles for all questions ───────────────────────────
  def detect_all_semantics!
    return if @semantics.any?
    @questions.each { |q| @semantics[q.id] = detect_question(q) }
  end

  def detect_question(q)
    title  = q.title.downcase
    qtype  = q.question_type.to_s
    n_resp = @total_responses

    # Load answers for this question
    answers = Answer.where(question_id: q.id, response_id: @completed_ids)
    n_ans   = answers.count
    return { role: :empty } if n_ans == 0

    # ── 1. NPS (by type) ──────────────────────────────────────────────
    if qtype == "nps"
      nums  = answers.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
      avg   = nums.any? ? (nums.sum.to_f / nums.size).round(2) : nil
      dist  = (0..10).map { |v| { "value" => v.to_s, "count" => nums.count(v) } }
      detractors = nums.count { |v| v <= 6 }
      passives   = nums.count { |v| [7,8].include?(v) }
      promoters  = nums.count { |v| v >= 9 }
      nps_score  = n_ans > 0 ? ((promoters - detractors).to_f / n_ans * 100).round : 0
      return {
        role: :nps, chart_type: "nps_bar",
        avg: avg, dist: dist, total: nums.size,
        nps_score: nps_score, promoters: promoters, passives: passives, detractors: detractors,
        data_summary: "avg=#{avg}/10, NPS=#{nps_score}%, promoters=#{promoters}, passives=#{passives}, detractors=#{detractors}, dist=[#{dist.map{|d| "#{d['value']}:#{d['count']}"}.reject{|s| s.end_with?(":0")}.join(', ')}]"
      }
    end

    # ── 2. Rating / linear_scale (by type) ───────────────────────────
    if %w[rating linear_scale].include?(qtype)
      nums = answers.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f)
      rs   = ReportAnalytics.rating_stats(nums, qtype, q.settings)
      dist = rs[:dist].map { |d| { "value" => d[:value].to_s, "count" => d[:count] } }
      return {
        role: :numeric, chart_type: "rating_bar",
        avg: rs[:avg], max: rs[:max], dist: dist, total: rs[:total],
        data_summary: "avg=#{rs[:avg]}/#{rs[:max]}, n=#{rs[:total]}, dist=[#{dist.map{|d| "#{d['value']}:#{d['count']}"}.reject{|s| s.end_with?(":0")}.join(', ')}]"
      }
    end

    # ── 3. Text questions — detect by data pattern first ──────────────
    if %w[short_text long_text].include?(qtype)
      texts = answers.where.not(text_value: [nil, ""]).pluck(:text_value).map(&:strip).reject(&:blank?)
      return { role: :empty } if texts.empty?

      # 3a. PCT detection (≥40% of answers parse as numbers 1-100)
      pct_vals = texts.filter_map { |t| self.class.parse_pct(t) }
      if pct_vals.size >= texts.size * 0.4
        avg  = (pct_vals.sum / pct_vals.size).round(1)
        dist = self.class.build_pct_distribution(pct_vals)
        return {
          role: :pct, chart_type: "distribution_bar", processing: "parse_percent",
          values: pct_vals, avg: avg, min: pct_vals.min.round(1), max: pct_vals.max.round(1),
          distribution: dist, total: pct_vals.size,
          data_summary: "avg=#{avg}%, range=#{pct_vals.min.round}–#{pct_vals.max.round}%, n=#{pct_vals.size}, dist=[#{dist.map{|d| "#{d[:label]}:#{d[:count]}"}.join(', ')}]"
        }
      end

      # 3b. Theme/suggestion detection — checked BEFORE tool detection so an
      # explicit suggestion/feedback question (which often mentions tool names in
      # passing) is grouped into themes, not mis-classified as a "tools" question.
      is_suggestion = title.match?(/đề xuất|gợi ý|kiến nghị|suggest|recommend|cải thiện|improve|góp ý|ý kiến|chia sẻ|share|mong muốn|wish|expect|propose|feedback|cần|nên/)
      if is_suggestion
        themes = self.class.extract_themes(texts, n_resp)
        quotes = texts.select { |t| t.length >= 40 }.sort_by(&:length).last(6).map { |t| t.truncate(300) }
        # Feed the AI raw samples (not the domain-locked keyword themes) so insights
        # aren't biased toward a fixed taxonomy. Actual chart themes come from
        # ReportAnalytics.categorize_themes at generation time.
        sample = texts.select { |t| t.length >= 20 }.sample(4).map { |t| t.truncate(90) }
        return {
          role: :themes, chart_type: "theme_bar", processing: "extract_themes",
          options: themes, quotes: quotes, texts: texts, total: texts.size,
          data_summary: "n=#{texts.size} suggestions, samples: #{sample.inspect}"
        }
      end

      # 3c. Tool detection (answers are AI tool names) — only for non-suggestion
      # questions, and require the title to actually ask "which tool" OR a strong
      # majority of answers to be tool names (not just an incidental mention).
      title_is_tools = title.match?(/\b(ai nào|công cụ|tool|phần mềm|software|app nào|nền tảng|platform)\b/)
      tool_answers = texts.select { |t| t.match?(/claude|chatgpt|gemini|gpt|cursor|copilot|codex|deepseek|midjourney|perplexity|antigravity|trae/i) }
      if (title_is_tools && tool_answers.size >= [texts.size * 0.3, 2].min) ||
         tool_answers.size >= texts.size * 0.6
        opts = self.class.aggregate_tools(texts, n_resp)
        return {
          role: :tools, chart_type: "bar", processing: "normalize_tools",
          options: opts, texts: texts, total: n_resp,
          data_summary: "tools: #{opts.first(6).map{|o| "#{o[:label]}=#{o[:count]}"}.join(', ')}"
        }
      end

      # 3d. Notable quotes
      long_texts = texts.select { |t| t.length >= 40 }
      if long_texts.size >= [texts.size * 0.5, 3].min
        quotes = long_texts.sort_by(&:length).last(8).map { |t| t.truncate(300) }
        return {
          role: :quotes, chart_type: "quotes",
          quotes: quotes, total: texts.size,
          data_summary: "n=#{texts.size}, sample: \"#{texts.first.to_s.truncate(80)}\""
        }
      end

      # 3e. Short open text — skip chart
      return { role: :text, chart_type: nil, total: texts.size }
    end

    # ── 4. Choice questions (single_choice, multiple_choice, dropdown) ──
    if %w[single_choice multiple_choice dropdown].include?(qtype)
      total_ans = answers.count
      opts = q.question_options.order(:position).filter_map do |opt|
        cnt = answers.where(*self.class.option_match(opt.id)).count
        cnt > 0 ? { label: opt.label, count: cnt, pct: (cnt.to_f / n_resp * 100).round(1) } : nil
      end
      return { role: :empty } if opts.empty?

      top_str = opts.sort_by { |o| -o[:count] }.first(5).map { |o| "#{o[:label]}=#{o[:count]}(#{o[:pct]}%)" }.join(", ")
      data_sum = "n=#{total_ans}, options: #{top_str}"

      # ── 4a. Grouping question (dept/role/team) — exempt from degenerate collapse
      if title.match?(/\b(bộ phận|phòng ban|team|department|division|unit|vị trí|position|role|chức vụ|cấp bậc|seniority|nhóm|group)\b/) &&
         qtype.in?(%w[single_choice dropdown])
        return { role: :grouping, chart_type: "doughnut", options: opts, total: n_resp, data_summary: data_sum }
      end

      # ── 4a′. Near-unanimous single-answer question → compact stat, not a chart
      if qtype != "multiple_choice" && ReportAnalytics.degenerate_choice?(opts)
        top = opts.max_by { |o| o[:count] }
        return { role: :single_stat, chart_type: "single_stat",
                 top_option: top[:label], top_pct: top[:pct], options: opts, total: n_resp,
                 data_summary: "#{top[:pct]}% #{top[:label]} (n=#{total_ans})" }
      end

      # ── 4b. Frequency question ────────────────────────────────────
      if title.match?(/tần suất|bao lâu|mỗi ngày|hàng ngày|daily|weekly|thường xuyên|regularly|frequency|how often/)
        top_opt = opts.max_by { |o| o[:count] }
        return { role: :frequency, chart_type: "doughnut", options: opts, total: n_resp,
                 top_option: top_opt&.dig(:label),
                 data_summary: "n=#{total_ans}, top=#{top_opt&.dig(:label)}(#{top_opt&.dig(:count)}), #{data_sum}" }
      end

      # ── 4c. Tool question (multiple_choice with tool names in options) ──
      if title.match?(/công cụ|tool|phần mềm|software|app|ứng dụng|platform/) ||
         opts.any? { |o| o[:label].match?(/claude|chatgpt|gemini|gpt|cursor|codex/i) }
        sorted = opts.sort_by { |o| -o[:count] }
        return { role: :tools, chart_type: "bar", options: sorted, total: n_resp, data_summary: data_sum }
      end

      # ── 4d. Challenges / pain points ─────────────────────────────
      if title.match?(/khó khăn|thách thức|challenge|difficulty|pain|problem|issue|obstacle|barrier|vấn đề gặp|gặp phải|khó|cản trở|rào cản/)
        sorted = opts.sort_by { |o| -o[:count] }
        return { role: :challenges, chart_type: "horizontal_bar", options: sorted, total: n_resp, data_summary: data_sum }
      end

      # ── 4e. Usage / purpose ───────────────────────────────────────
      if title.match?(/mục đích|cách sử dụng|sử dụng.*cho|dùng.*để|use.*for|use case|used for|purpose|tasks?|công việc/)
        sorted = opts.sort_by { |o| -o[:count] }
        return { role: :usage, chart_type: "horizontal_bar", options: sorted, total: n_resp, data_summary: data_sum }
      end

      # ── 4f. Default by option count ───────────────────────────────
      ct = opts.size <= 6 ? "doughnut" : "bar"
      role = qtype == "multiple_choice" ? :multi_choice : :choice
      sorted = qtype == "multiple_choice" ? opts.sort_by { |o| -o[:count] } : opts
      { role: role, chart_type: ct, options: sorted, total: n_resp, data_summary: data_sum }
    else
      { role: :unknown, chart_type: nil }
    end
  end

  # ── Build sections from semantics ────────────────────────────────────
  def build_sections
    by_role = @questions.group_by { |q| @semantics[q.id]&.dig(:role) || :unknown }
    covered = Set.new
    sections = []

    # Prefer role-detected grouping questions; fall back to the core's broader
    # segment-dimension detector so we never miss an obvious group-by question.
    grouping_qs  = qs_for(:grouping).presence ||
                   ReportAnalytics.grouping_questions(@questions).reject { |q| @semantics[q.id]&.dig(:role) == :frequency }
    tool_qs      = qs_for(:tools)
    pct_qs       = qs_for(:pct)
    nps_qs       = qs_for(:nps)
    numeric_qs   = qs_for(:numeric)
    challenge_qs = qs_for(:challenges)
    usage_qs     = qs_for(:usage)
    freq_qs      = qs_for(:frequency)
    theme_qs     = qs_for(:themes)
    quote_qs     = qs_for(:quotes)
    choice_qs    = qs_for(:choice) + qs_for(:multi_choice)

    # ── Section 1: Thành phần người tham gia ───────────────────────
    cards = []
    (grouping_qs + freq_qs + qs_for(:single_stat)).each do |q|
      cards << mk_card(q, @semantics[q.id][:chart_type], nil, 6)
      covered << q.id
    end
    tool_qs.each do |q|
      sem = @semantics[q.id]
      cards << mk_card(q, sem[:chart_type], sem[:processing], 6)
      covered << q.id
    end
    if cards.any?
      sections << { "id" => "s-demo", "title" => "Thành phần người tham gia",
                    "layout" => "grid-2", "cards" => cards }
    end

    # ── Section 2: Mức độ tiết kiệm thời gian ──────────────────────
    if pct_qs.any?
      cards = pct_qs.map do |q|
        covered << q.id
        mk_card(q, "distribution_bar", "parse_percent", 6)
      end
      # Cross-tab if grouping question exists
      if grouping_qs.any?
        cards << {
          "question_id"          => nil,
          "chart_type"           => "cross_tab_grouped_bar",
          "title"                => "So sánh theo #{grouping_qs.first.title.truncate(30)}",
          "group_by_question_id" => grouping_qs.first.id,
          "value_question_ids"   => pct_qs.map(&:id),
          "processing"           => "parse_percent",
          "span"                 => 12
        }
      end
      # Neutral fallback title — the AI step renames it from the % questions'
      # actual content, so it isn't locked to "time savings".
      sections << { "id" => "s-savings", "title" => "Phân tích định lượng",
                    "layout" => "grid-2", "cards" => cards }
    end

    # ── Section 3: Đánh giá chất lượng & trải nghiệm ───────────────
    rating_cards = []
    (nps_qs + numeric_qs).each do |q|
      covered << q.id
      ct = @semantics[q.id][:chart_type]
      rating_cards << mk_card(q, ct, nil, ct == "nps_bar" ? 12 : 12)
    end
    # Cross-tab: compare rating scores across groups (e.g. satisfaction by dept).
    if rating_cards.any? && grouping_qs.any? && numeric_qs.any?
      rating_cards << {
        "question_id"          => nil,
        "chart_type"           => "cross_tab_grouped_bar",
        "title"                => "So sánh theo #{grouping_qs.first.title.truncate(30)}",
        "group_by_question_id" => grouping_qs.first.id,
        "value_question_ids"   => numeric_qs.map(&:id),
        "span"                 => 12
      }
    end
    if rating_cards.any?
      sections << { "id" => "s-ratings", "title" => "Đánh giá chất lượng & trải nghiệm",
                    "layout" => "grid-2", "cards" => rating_cards }
    end

    # ── Section 4: Khó khăn & Ý kiến người dùng ────────────────────
    s4_cards = []
    (challenge_qs + usage_qs).each do |q|
      covered << q.id
      s4_cards << mk_card(q, @semantics[q.id][:chart_type], nil, 6)
    end
    quote_qs.first(2).each do |q|
      covered << q.id
      s4_cards << { "question_id" => q.id, "chart_type" => "quotes",
                    "title" => "Nhận xét đáng chú ý", "span" => 6 }
    end
    if s4_cards.any?
      sections << { "id" => "s-challenges", "title" => "Khó khăn & Ý kiến người dùng",
                    "layout" => "grid-2", "cards" => s4_cards }
    end

    # ── Section 5: Đề xuất & Khuyến nghị ───────────────────────────
    s5_cards = []
    theme_qs.each do |q|
      covered << q.id
      s5_cards << { "question_id" => q.id, "chart_type" => "theme_bar",
                    "processing" => "extract_themes", "title" => "Nhóm đề xuất từ nhân viên", "span" => 6 }
    end
    # Remaining quotes not yet shown
    quote_qs.reject { |q| covered.include?(q.id) }.each do |q|
      covered << q.id
      s5_cards << { "question_id" => q.id, "chart_type" => "quotes",
                    "title" => "Nhận xét đáng chú ý", "span" => 6 }
    end
    if s5_cards.any?
      sections << { "id" => "s-recs", "title" => "Đề xuất & Khuyến nghị",
                    "layout" => "grid-2", "cards" => s5_cards }
    end

    # ── Section 6: Remaining choice questions ───────────────────────
    remain = choice_qs.reject { |q| covered.include?(q.id) }
    if remain.any?
      cards = remain.map do |q|
        sem = @semantics[q.id]
        covered << q.id
        mk_card(q, sem[:chart_type] || "bar", nil, 6)
      end
      sections << { "id" => "s-other", "title" => "Phân tích bổ sung",
                    "layout" => "grid-2", "cards" => cards }
    end

    sections
  end

  # ── Build KPIs from semantics ────────────────────────────────────────
  def build_kpis
    kpis = [{ "label" => "Người tham gia", "source" => "total_responses", "color" => "#4361ee" }]

    pct_qs = qs_for(:pct)
    colors = %w[#06b6d4 #10b981 #f59e0b #8b5cf6]
    pct_qs.first(2).each_with_index do |q, i|
      avg = @semantics[q.id][:avg]
      next unless avg
      kpis << { "label" => q.title.truncate(22), "source" => "question_avg_pct",
                "question_id" => q.id, "color" => colors[i] }
    end

    qs_for(:nps).first(1).each do |q|
      kpis << { "label" => "Điểm NPS trung bình", "source" => "question_avg",
                "question_id" => q.id, "color" => "#f59e0b" }
    end

    # Frequency question → show top option % + its label
    qs_for(:frequency).first(1).each do |q|
      sem = @semantics[q.id]
      top = sem[:options]&.max_by { |o| o[:count] }
      next unless top && top[:pct].to_f > 0
      # label = "Hàng ngày" (top option name), value = "87%" shown by question_top_option
      kpis << { "label" => top[:label].truncate(24), "source" => "question_top_option",
                "question_id" => q.id, "color" => "#8b5cf6" }
    end

    kpis
  end

  # ── Helpers ─────────────────────────────────────────────────────────
  def qs_for(*roles)
    @questions.select { |q| roles.include?(@semantics[q.id]&.dig(:role)) }
  end

  def mk_card(q, chart_type, processing, span)
    { "question_id" => q.id, "chart_type" => chart_type,
      "title" => q.title, "span" => span }.tap { |c| c["processing"] = processing if processing }
  end

  def cross_tab_card(group_q, value_qs, processing)
    card = {
      "question_id"          => nil,
      "chart_type"           => "cross_tab_grouped_bar",
      "title"                => "So sánh theo #{group_q.title.truncate(30)}",
      "group_by_question_id" => group_q.id,
      "value_question_ids"   => value_qs.map(&:id),
      "span"                 => 12
    }
    card["processing"] = processing if processing
    card
  end
end
