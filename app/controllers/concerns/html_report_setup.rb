module HtmlReportSetup
  extend ActiveSupport::Concern

  # ── Tool name normalization ────────────────────────────────────────────────
  TOOL_NORMALIZE = {
    /chatgpt|chat\s*gpt|gpt[-\s]?[34]/i          => "ChatGPT",
    /claude/i                                      => "Claude",
    /gemini|bard/i                                 => "Gemini",
    /copilot/i                                     => "GitHub Copilot",
    /midjourney/i                                  => "Midjourney",
    /dall[\s-]?e/i                                 => "DALL-E",
    /notion\s*ai/i                                 => "Notion AI",
    /grammarly/i                                   => "Grammarly",
    /perplexity/i                                  => "Perplexity",
    /bing\s*(?:ai|chat)?/i                         => "Bing AI",
    /google\s*(?:ai|bard|search)/i                 => "Google AI",
    /stability[\s-]?ai|stable\s*diffusion/i        => "Stable Diffusion",
    /canva/i                                       => "Canva AI",
    /jasper/i                                      => "Jasper",
    /writesonic|copy[\s.]?ai|anyword/i             => "AI Writing Tools",
  }.freeze

  # ── Theme keyword rules for long-text answers ─────────────────────────────
  THEME_RULES = [
    { label: "Tự động hóa quy trình",  kws: %w[tự động automation workflow quy trình] },
    { label: "Tạo nội dung / Viết lách", kws: %w[viết văn content nội dung soạn thảo] },
    { label: "Phân tích dữ liệu",       kws: %w[phân tích data dữ liệu báo cáo excel] },
    { label: "Tra cứu & Tìm kiếm",      kws: %w[tra cứu tìm kiếm search thông tin] },
    { label: "Dịch thuật",              kws: %w[dịch translate ngôn ngữ language] },
    { label: "Lập trình / Code",        kws: %w[code lập trình debug script] },
    { label: "Thiết kế hình ảnh",       kws: %w[thiết kế design hình ảnh image vẽ] },
    { label: "Tóm tắt tài liệu",        kws: %w[tóm tắt summary tóm lược tài liệu] },
    { label: "Lên kế hoạch",            kws: %w[kế hoạch plan lịch schedule] },
    { label: "Đào tạo & Học tập",       kws: %w[học đào tạo training giảng dạy] },
  ].freeze

  # ── PCT distribution buckets ───────────────────────────────────────────────
  PCT_BUCKETS = [
    ["<20%",  0,  19],
    ["20–29%", 20, 29],
    ["30–39%", 30, 39],
    ["40–49%", 40, 49],
    ["50–59%", 50, 59],
    ["60–69%", 60, 69],
    ["70–79%", 70, 79],
    ["80–89%", 80, 89],
    ["≥90%",  90, 100],
  ].freeze

  # ─────────────────────────────────────────────────────────────────────────
  def call_html_report_setup
    @questions        = @survey.questions.includes(:question_options).order(:position)
    @total_responses  = @survey.responses.completed.count
    @report_structure = @survey.settings&.dig("report_structure")

    responses   = @survey.responses.completed.includes(:answers).to_a
    all_answers = responses.flat_map(&:answers)

    # Build option_id → label lookup
    opt_label = @questions.flat_map(&:question_options)
                          .each_with_object({}) { |o, h| h[o.id.to_i] = o.label }

    # Build per-response lookup: response_id → {question_id → answer}
    resp_answers = responses.each_with_object({}) do |resp, h|
      h[resp.id] = resp.answers.index_by(&:question_id)
    end

    # Try to identify name question and dept question from structure semantic hints
    # (AI may flag these via chart_type "hidden" + semantic key)
    name_qid = nil; dept_qid = nil
    @report_structure&.dig("sections")&.each do |sec|
      sec["cards"]&.each do |c|
        case c["semantic"]
        when "respondent_name" then name_qid = c["question_id"]&.to_i
        when "respondent_dept" then dept_qid = c["question_id"]&.to_i
        end
      end
    end
    # Fallback: guess name/dept from question titles
    unless name_qid
      name_q = @questions.find { |q| q.title.match?(/\b(họ tên|tên|name)\b/i) && q.question_type.in?(%w[short_text long_text]) }
      name_qid = name_q&.id
    end
    unless dept_qid
      dept_q = @questions.find { |q| q.title.match?(/\b(bộ phận|phòng ban|team|department)\b/i) && q.question_type.in?(%w[single_choice dropdown]) }
      dept_qid = dept_q&.id
    end

    # Build respondent meta: response_id → {name, dept}
    @resp_meta = responses.each_with_object({}) do |resp, h|
      ans_map = resp_answers[resp.id] || {}
      name = ans_map[name_qid]&.text_value&.presence if name_qid
      dept_ans = ans_map[dept_qid] if dept_qid
      dept = if dept_ans && dept_qid
               dept_q2 = @questions.find { |q| q.id == dept_qid }
               opt_label[Array(dept_ans.option_ids).map(&:to_i).first]
             end
      h[resp.id] = { name: name, dept: dept }.compact
    end

    # Per-question stats (with optional processing hints from structure)
    processing_map = build_processing_map(@report_structure)

    @question_stats = {}
    @questions.each do |q|
      answers    = all_answers.select { |a| a.question_id == q.id }
      card_meta  = processing_map[q.id] || {}
      @question_stats[q.id] = compute_question_stats(q, answers, opt_label, @total_responses,
                                                      processing: card_meta[:processing],
                                                      ai_options: card_meta[:ai_options],
                                                      resp_meta: @resp_meta)
    end

    # Cross-tab stats (one key per cross-tab card in structure)
    @cross_tab_data = {}
    if @report_structure
      @report_structure["sections"]&.each do |sec|
        sec["cards"]&.each do |card|
          next unless card["chart_type"] == "cross_tab_grouped_bar"
          group_qid  = card["group_by_question_id"]&.to_i
          value_qids = Array(card["value_question_ids"]).map(&:to_i)
          proc_hint  = card["processing"]
          next if group_qid.blank? || value_qids.empty?

          ct_key = "ct_#{group_qid}_#{value_qids.join('_')}"
          @cross_tab_data[ct_key] = compute_cross_tab(
            group_qid, value_qids, proc_hint, all_answers, resp_answers, @questions
          )
        end
      end
    end

    # KPI values
    @kpi_values = build_kpi_values(@report_structure&.dig("kpis") || [], @question_stats, @total_responses)

    # Date range
    @survey_date_range = begin
      dates = responses.map(&:completed_at).compact
      "#{dates.min.strftime('%d/%m/%Y')} – #{dates.max.strftime('%d/%m/%Y')}" if dates.any?
    end
  end

  private

  # Build question_id → {processing, ai_options} map from structure
  def build_processing_map(structure)
    map = {}
    structure&.dig("sections")&.each do |sec|
      sec["cards"]&.each do |card|
        qid = card["question_id"]&.to_i
        next if qid.blank?
        map[qid] = { processing: card["processing"], ai_options: card["ai_options"] }
      end
    end
    map
  end

  # ── Core per-question stats ───────────────────────────────────────────────
  def compute_question_stats(q, answers, opt_label, total_responses, processing: nil, ai_options: nil, resp_meta: {}) # rubocop:disable Metrics/MethodLength
    base = { id: q.id, title: q.title, question_type: q.question_type, count: answers.size }

    # ── AI pre-computed options (stored in report structure) ──
    if ai_options.present? && %w[short_text long_text open_ended text].include?(q.question_type)
      opts = ai_options.map { |o| { label: o["label"], count: o["count"].to_i, pct: o["pct"].to_f } }
      texts = answers.map(&:text_value).compact.reject(&:blank?)
      rich_quotes = answers.select { |a| a.text_value.to_s.length >= 40 }
                           .sort_by { |a| a.text_value.to_s.length }.last(6)
                           .map { |a| meta = resp_meta[a.response_id] || {}
                                      { text: a.text_value.to_s.truncate(300), name: meta[:name], dept: meta[:dept] } }
      return base.merge(options: opts, quotes: rich_quotes.map { |q| q[:text] },
                        rich_quotes: rich_quotes, total: texts.size, processing: "ai_themes")
    end

    # ── Special processing overrides ──
    case processing
    when "parse_percent"
      return compute_pct_stats(base, answers, total_responses)
    when "normalize_tools"
      return compute_tool_stats(base, answers, total_responses)
    when "extract_themes"
      return compute_theme_stats(base, answers, total_responses)
    end

    # ── Standard by question_type ──
    case q.question_type
    when "single_choice", "multiple_choice", "dropdown"
      option_counts = q.question_options.order(:position).map do |opt|
        count = answers.count { |a| Array(a.option_ids).map(&:to_i).include?(opt.id) }
        { id: opt.id, label: opt.label, count: count,
          pct: total_responses > 0 ? (count.to_f / total_responses * 100).round(1) : 0 }
      end.reject { |o| o[:count].zero? }
      base.merge(options: option_counts, total: total_responses)

    when "rating", "linear_scale", "nps"
      vals = answers.filter_map { |a| a.numeric_value&.to_f }
      if vals.any?
        max_scale = q.question_type == "nps" ? 10 : [vals.max.to_i, 5].max
        start_val = q.question_type == "nps" ? 0 : 1
        dist = (start_val..max_scale).map do |v|
          c = vals.count { |n| n.round == v }
          { label: v.to_s, count: c, pct: vals.size > 0 ? (c.to_f / vals.size * 100).round(1) : 0 }
        end
        base.merge(values: vals, avg: (vals.sum / vals.size).round(2),
                   min: vals.min, max: vals.max, max_scale: max_scale,
                   distribution: dist, total: vals.size)
      else
        base.merge(values: [], avg: nil, distribution: [], total: 0)
      end

    when "short_text", "long_text"
      texts  = answers.map(&:text_value).compact.reject(&:blank?)
      # Build rich quotes with author metadata when available
      rich_quotes = answers.select { |a| a.text_value.to_s.length >= 40 }
                           .sort_by { |a| a.text_value.to_s.length }
                           .last(8)
                           .map do |a|
        meta = resp_meta[a.response_id] || {}
        { text: a.text_value.to_s.truncate(300), name: meta[:name], dept: meta[:dept] }
      end
      quotes = rich_quotes.map { |q| q[:text] }  # backward compat
      base.merge(texts: texts, quotes: quotes, rich_quotes: rich_quotes, total: texts.size)

    when "matrix"
      rows = q.question_options.where(option_type: "row").order(:position)
      cols = q.question_options.where(option_type: "column").order(:position)
      matrix = rows.map do |row|
        col_counts = cols.map do |col|
          count = answers.count { |a|
            Array(a.option_ids).map(&:to_i).include?(row.id) &&
              a.settings&.dig("matrix", col.id.to_s).present?
          }
          { label: col.label, count: count }
        end
        { label: row.label, cols: col_counts }
      end
      base.merge(matrix: matrix, rows: rows.map(&:label), cols: cols.map(&:label), total: answers.size)

    else
      texts = answers.map(&:text_value).compact.reject(&:blank?)
      base.merge(texts: texts, total: texts.size)
    end
  end

  # ── Parse percentage from text answers ───────────────────────────────────
  def parse_pct_value(text)
    n = text.to_s.gsub(/[~≈≤≥\s%]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f
    (n && n > 0 && n <= 100) ? n : nil
  end

  def build_pct_distribution(vals)
    PCT_BUCKETS.filter_map do |label, lo, hi|
      count = if lo == 0
                vals.count { |v| v < 20 }
              elsif hi == 100
                vals.count { |v| v >= 90 }
              else
                vals.count { |v| v >= lo && v <= hi }
              end
      count > 0 ? { label: label, count: count, pct: vals.size > 0 ? (count.to_f / vals.size * 100).round(1) : 0 } : nil
    end
  end

  def compute_pct_stats(base, answers, total_responses)
    vals = answers.filter_map { |a| parse_pct_value(a.text_value) }
    dist = build_pct_distribution(vals)
    base.merge(
      processing: "parse_percent",
      values:     vals,
      avg:        vals.any? ? (vals.sum / vals.size).round(1) : nil,
      min:        vals.min,
      max:        vals.max,
      distribution: dist,
      total:      vals.size
    )
  end

  # ── Normalize tool names from text answers ────────────────────────────────
  def normalize_tool(text)
    text = text.to_s.strip
    match = TOOL_NORMALIZE.find { |pat, _| text.match?(pat) }
    return match.last if match
    # Capitalize first letter, take first 3 words
    parts = text.split(/\s+/).first(3)
    parts.map { |p| p.length > 2 ? p.capitalize : p }.join(" ")
  end

  def compute_tool_stats(base, answers, total_responses)
    tc = Hash.new(0)
    answers.each do |a|
      raw = a.text_value.to_s
      # Split by common separators
      parts = raw.split(/[,，、;；\n\/]+/).map(&:strip).reject(&:blank?)
      parts.each { |p| tc[normalize_tool(p)] += 1 if p.length > 1 }
    end
    opts = tc.sort_by { |_, c| -c }.first(15).map do |name, count|
      { label: name, count: count,
        pct: total_responses > 0 ? (count.to_f / total_responses * 100).round(1) : 0 }
    end
    base.merge(processing: "normalize_tools", options: opts, total: total_responses)
  end

  # ── Keyword-group themes from long text ───────────────────────────────────
  def compute_theme_stats(base, answers, total_responses)
    texts = answers.map(&:text_value).compact.reject(&:blank?)
    theme_counts = THEME_RULES.filter_map do |rule|
      count = texts.count { |t| rule[:kws].any? { |kw| t.downcase.include?(kw) } }
      count > 0 ? { label: rule[:label], count: count,
                    pct: total_responses > 0 ? (count.to_f / total_responses * 100).round(1) : 0 } : nil
    end.sort_by { |t| -t[:count] }

    # Also keep quotes for context
    quotes = texts.select { |t| t.length >= 40 }.sort_by(&:length).last(6).map { |t| t.truncate(300) }
    base.merge(processing: "extract_themes", options: theme_counts, quotes: quotes, total: texts.size)
  end

  # ── Cross-tab computation ────────────────────────────────────────────────
  # group_by_qid: question whose options define the groups (e.g. department)
  # value_qids: questions whose values are aggregated per group (e.g. savings %)
  # Returns: { labels: [...], datasets: [{label:, data:[], color:}], totals: {label=>n} }
  def compute_cross_tab(group_qid, value_qids, proc_hint, all_answers, resp_answers, questions)
    group_q    = questions.find { |q| q.id == group_qid }
    value_qs   = questions.select { |q| value_qids.include?(q.id) }
    return nil unless group_q && value_qs.any?

    # Get group option labels
    group_options = group_q.question_options.order(:position).map { |o| [o.id, o.label] }
    return nil if group_options.empty?

    datasets = value_qs.map.with_index do |vq, i|
      colors = %w[#4361ee #06b6d4 #10b981 #f59e0b #ef4444 #8b5cf6]
      color  = colors[i % colors.length]

      avgs = group_options.map do |opt_id, _label|
        # Responses that selected this group option
        group_resp_ids = all_answers.select { |a|
          a.question_id == group_qid &&
            Array(a.option_ids).map(&:to_i).include?(opt_id.to_i)
        }.map(&:response_id)

        # Their answers to the value question
        val_answers = all_answers.select { |a|
          a.question_id == vq.id && group_resp_ids.include?(a.response_id)
        }

        if proc_hint == "parse_percent"
          vals = val_answers.filter_map { |a| parse_pct_value(a.text_value) }
          vals.any? ? (vals.sum / vals.size).round(1) : 0
        else
          vals = val_answers.filter_map { |a| a.numeric_value&.to_f }
          vals.any? ? (vals.sum / vals.size).round(2) : 0
        end
      end

      { label: vq.title, data: avgs, color: color }
    end

    group_counts = group_options.map do |opt_id, _|
      all_answers.count { |a|
        a.question_id == group_qid &&
          Array(a.option_ids).map(&:to_i).include?(opt_id.to_i)
      }
    end

    # ── Filter out groups with zero respondents ──────────────────────────
    active_indices = group_counts.each_with_index.filter_map { |cnt, i| i if cnt > 0 }
    return nil if active_indices.empty?

    filtered_labels = group_options.map(&:last).values_at(*active_indices)
    filtered_counts = group_counts.values_at(*active_indices)
    filtered_datasets = datasets.map do |ds|
      ds.merge(data: ds[:data].values_at(*active_indices))
    end

    {
      labels:       filtered_labels,
      datasets:     filtered_datasets,
      group_counts: filtered_counts
    }
  end

  # ── KPI computation ───────────────────────────────────────────────────────
  def build_kpi_values(kpi_configs, question_stats, total_responses)
    kpi_configs.map do |kpi|
      value = case kpi["source"]
              when "total_responses"
                total_responses.to_s
              when "question_avg"
                stats = question_stats[kpi["question_id"]&.to_i]
                stats&.dig(:avg)&.then { |v| v.round(1).to_s } || "—"
              when "question_avg_pct"
                stats = question_stats[kpi["question_id"]&.to_i]
                avg   = stats&.dig(:avg)
                avg ? "#{avg}%" : "—"
              when "question_top_option"
                # Show percentage of top option (e.g. "87%") not raw text
                stats = question_stats[kpi["question_id"]&.to_i]
                top   = stats&.dig(:options)&.max_by { |o| o[:count] }
                top ? "#{top[:pct]}%" : "—"
              else
                "—"
              end
      { label: kpi["label"], value: value, color: kpi["color"] || "#4361ee" }
    end
  end
end
