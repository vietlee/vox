module HtmlReportSetup
  extend ActiveSupport::Concern

  TOOL_NORMALIZE = {
    /claude\s*code/i      => "Claude Code",
    /claude\s*co-?work/i  => "Claude",
    /claude/i             => "Claude",
    /chat\s*gpt/i         => "ChatGPT",
    /chatgpt/i            => "ChatGPT",
    /codex/i              => "Codex",
    /gemini/i             => "Gemini",
    /cursor/i             => "Cursor",
    /github\s*copilot/i   => "GitHub Copilot",
    /copilot/i            => "GitHub Copilot",
    /deepseek/i           => "DeepSeek",
    /antigravity/i        => "Antigravity",
    /anti\s*gravity/i     => "Antigravity",
    /perplexi/i           => "Perplexity",
    /notebooklm/i         => "NotebookLM",
    /kiro/i               => "Kiro",
    /trae/i               => "Trae",
  }.freeze

  THEME_RULES = [
    { label: "Cung cấp tài khoản AI",         kws: ["tài khoản", "account", "cung cấp"] },
    { label: "Xây dựng quy trình chuẩn",       kws: ["quy trình", "chuẩn", "standard"] },
    { label: "Tổ chức buổi sharing/training",   kws: ["sharing", "buổi", "training", "chia sẻ"] },
    { label: "Hỗ trợ tài chính",               kws: ["tài chính", "chi phí", "tài trợ"] },
    { label: "Nguyên tắc bảo mật",             kws: ["bảo mật", "security", "nguyên tắc"] },
  ].freeze

  def call_html_report_setup # rubocop:disable Metrics/MethodLength
    @questions       = @survey.questions.includes(:question_options).order(:position)
    @total_responses = @survey.responses.completed.count
    @ai_analysis     = @survey.latest_ai_analysis
    responses        = @survey.responses.completed.includes(:answers).to_a
    all_answers      = responses.flat_map(&:answers)

    # Helper: find question by fuzzy keyword match on title
    find_q = ->(kws, types: nil) {
      @questions.find { |q|
        title = q.title.to_s.downcase.unicode_normalize rescue q.title.to_s.downcase
        match = kws.all? { |kw| title.include?(kw) }
        match &&= Array(types).include?(q.question_type) if types
        match
      }
    }

    # Helper: parse numeric % from text answer
    parse_pct = ->(text) {
      n = text.to_s.gsub(/[~≈%\s]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f
      (n && n > 0 && n <= 100) ? n : nil
    }

    # Helper: answers for a question
    q_answers = ->(q) { all_answers.select { |a| a.question_id == q.id } }

    # ── Identify key questions ────────────────────────────────────
    name_q         = find_q.call(["tên"], types: %w[short_text long_text])
    dept_q         = find_q.call(["bộ phận"])
    tool_q         = find_q.call(["ai nào"]) || find_q.call(["công cụ"])
    task_type_q    = find_q.call(["công việc nào"]) || find_q.call(["loại công việc"])
    task_savings_q = find_q.call(["task"])
    daily_savings_q= find_q.call(["mỗi ngày"])
    stage_q        = find_q.call(["giai đoạn"])
    challenge_q    = find_q.call(["khó khăn"])
    nps_q          = @questions.find { |q| q.question_type == "nps" }
    rating_qs      = @questions.select { |q| %w[rating linear_scale].include?(q.question_type) }
    suggest_q      = find_q.call(["đề xuất"]) || find_q.call(["chia sẻ"])
    support_q      = find_q.call(["hỗ trợ"]) || find_q.call(["mong muốn"])

    # ── Build option_id → label lookup for all questions ─────────
    opt_label = @questions.flat_map(&:question_options)
                          .each_with_object({}) { |o, h| h[o.id] = o.label }

    # Helper: does an answer select a given option?
    ans_has_opt = ->(a, opt_id) { Array(a.option_ids).map(&:to_i).include?(opt_id.to_i) }

    # ── Per-response lookup ───────────────────────────────────────
    resp_meta = {}
    responses.each do |r|
      ans = all_answers.select { |a| a.response_id == r.id }
      meta = { email: r.respondent_email.to_s }
      meta[:name] = ans.find { |a| a.question_id == name_q.id }&.text_value.to_s.strip if name_q
      if dept_q
        dept_ans = ans.find { |a| a.question_id == dept_q.id }
        dept_opt_id = Array(dept_ans&.option_ids).map(&:to_i).first
        meta[:dept] = opt_label[dept_opt_id].to_s if dept_opt_id
      end
      meta[:savings_task]  = parse_pct.call(ans.find { |a| a.question_id == task_savings_q.id }&.text_value.to_s)  if task_savings_q
      meta[:savings_daily] = parse_pct.call(ans.find { |a| a.question_id == daily_savings_q.id }&.text_value.to_s) if daily_savings_q
      resp_meta[r.id] = meta
    end

    # ── Department breakdown ──────────────────────────────────────
    @dept_data = if dept_q
      dept_q.question_options.order(:position).filter_map do |opt|
        count = all_answers.count { |a| a.question_id == dept_q.id && ans_has_opt.call(a, opt.id) }
        count > 0 ? { label: opt.label, count: count } : nil
      end
    else
      []
    end

    # ── Tools: parse & normalize free-text ───────────────────────
    @tool_counts = if tool_q
      tc = Hash.new(0)
      q_answers.call(tool_q).each do |a|
        a.text_value.to_s.split(/[,，、;；\n]+/).each do |part|
          part = part.strip
          next if part.blank?
          normalized = TOOL_NORMALIZE.find { |pat, _| part.match?(pat) }&.last || part.split.first(2).join(" ")
          tc[normalized] += 1 if normalized.present?
        end
      end
      tc.sort_by { |_, c| -c }.first(10).map { |name, count| { label: name, count: count } }
    else
      []
    end

    # ── Task types ───────────────────────────────────────────────
    @task_type_counts = if task_type_q
      task_type_q.question_options.order(:position).filter_map do |opt|
        count = all_answers.count { |a| a.question_id == task_type_q.id && ans_has_opt.call(a, opt.id) }
        count > 0 ? { label: opt.label, count: count } : nil
      end.sort_by { |c| -c[:count] }
    else
      []
    end

    # ── Stage breakdown ───────────────────────────────────────────
    @stage_counts = if stage_q
      stage_q.question_options.order(:position).filter_map do |opt|
        count = all_answers.count { |a| a.question_id == stage_q.id && ans_has_opt.call(a, opt.id) }
        count > 0 ? { label: opt.label.gsub(/Giai đoạn /i, ""), count: count } : nil
      end
    else
      []
    end

    # ── Savings ───────────────────────────────────────────────────
    def_buckets = [[0,29],[30,39],[40,49],[50,59],[60,69],[70,79],[80,89],[90,100]]
    make_dist = ->(vals) {
      def_buckets.map { |lo, hi|
        { label: "#{lo}–#{hi}%", count: vals.count { |v| v >= lo && v <= hi } }
      }.reject { |b| b[:count].zero? || b[:label] == "0–29%" && b[:count] == 0 }
    }

    task_savings_vals  = task_savings_q  ? q_answers.call(task_savings_q).filter_map  { |a| parse_pct.call(a.text_value) } : []
    daily_savings_vals = daily_savings_q ? q_answers.call(daily_savings_q).filter_map { |a| parse_pct.call(a.text_value) } : []

    @task_savings_dist  = make_dist.call(task_savings_vals)
    @daily_savings_dist = make_dist.call(daily_savings_vals)

    # ── Dept × savings cross-tab ──────────────────────────────────
    @dept_savings = if dept_q && (task_savings_q || daily_savings_q)
      @dept_data.map do |dept|
        dept_resp_ids = resp_meta.select { |_, m| m[:dept] == dept[:label] }.keys
        ts = dept_resp_ids.filter_map { |rid| resp_meta[rid][:savings_task] }
        ds = dept_resp_ids.filter_map { |rid| resp_meta[rid][:savings_daily] }
        {
          label:          dept[:label],
          count:          dept[:count],
          savings_task:   ts.any? ? (ts.sum / ts.size).round(1) : nil,
          savings_daily:  ds.any? ? (ds.sum / ds.size).round(1) : nil
        }
      end
    else
      []
    end

    # ── Rating questions ──────────────────────────────────────────
    @rating_stats = rating_qs.map do |q|
      vals = all_answers.select { |a| a.question_id == q.id && a.numeric_value.present? }
                        .map { |a| a.numeric_value.to_f }
      next nil if vals.empty?
      { id: q.id, title: q.title, mean: (vals.sum / vals.size).round(2),
        values: vals, max: vals.max.to_i.clamp(5, 10) }
    end.compact

    @nps_stats = if nps_q
      vals = all_answers.select { |a| a.question_id == nps_q.id && a.numeric_value.present? }
                        .map { |a| a.numeric_value.to_f }
      vals.any? ? { mean: (vals.sum / vals.size).round(2), values: vals } : nil
    end

    # ── Challenges ───────────────────────────────────────────────
    @challenge_counts = if challenge_q
      challenge_q.question_options.order(:position).filter_map do |opt|
        count = all_answers.count { |a| a.question_id == challenge_q.id && ans_has_opt.call(a, opt.id) }
        count > 0 ? { label: opt.label, count: count } : nil
      end.sort_by { |c| -c[:count] }
    else
      []
    end

    # ── Notable quotes ────────────────────────────────────────────
    quote_qs = [suggest_q, support_q].compact
    @notable_quotes = []
    quote_qs.each do |q|
      q_answers.call(q).each do |a|
        next if a.text_value.to_s.length < 60
        meta = resp_meta[a.response_id] || {}
        name = meta[:name].presence || meta[:email].split("@").first.presence || "Ẩn danh"
        @notable_quotes << {
          question: q.title.to_s.truncate(60),
          text:     a.text_value.to_s.truncate(350),
          name:     name,
          dept:     meta[:dept].presence
        }
      end
    end
    @notable_quotes = @notable_quotes.sort_by { |q| -q[:text].length }.first(6)

    # ── Request themes ────────────────────────────────────────────
    all_open_texts = ([suggest_q, support_q].compact).flat_map { |q| q_answers.call(q).map(&:text_value) }.compact
    @request_themes = THEME_RULES.filter_map do |rule|
      count = all_open_texts.count { |t|
        tl = t.to_s.downcase
        rule[:kws].any? { |kw| tl.include?(kw) }
      }
      count > 0 ? { label: rule[:label], count: count } : nil
    end.sort_by { |t| -t[:count] }

    # ── KPIs ──────────────────────────────────────────────────────
    adoption_q = @questions.find { |q| q.title.to_s.downcase.include?("có đang sử dụng") || q.title.to_s.downcase.include?("tần suất") }
    daily_users = if adoption_q
      opts = adoption_q.question_options.select { |o| o.label.to_s.downcase.include?("hàng ngày") || o.label.to_s.downcase.include?("thường xuyên") }
      opts.sum { |o| all_answers.count { |a| a.question_id == adoption_q.id && ans_has_opt.call(a, o.id) } }
    else
      @total_responses
    end

    @kpis = {
      total:         @total_responses,
      savings_task:  task_savings_vals.any?  ? "#{(task_savings_vals.sum / task_savings_vals.size).round(0)}%"  : nil,
      savings_daily: daily_savings_vals.any? ? "#{(daily_savings_vals.sum / daily_savings_vals.size).round(0)}%" : nil,
      nps_avg:       @nps_stats              ? @nps_stats[:mean].to_s : nil,
      daily_pct:     @total_responses > 0    ? "#{(daily_users.to_f / @total_responses * 100).round(0)}%" : nil,
    }

    @survey_date_range = begin
      dates = responses.map(&:completed_at).compact
      "#{dates.min.strftime('%d/%m/%Y')} – #{dates.max.strftime('%d/%m/%Y')}" if dates.any?
    end
  end
end
