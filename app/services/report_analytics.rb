# ReportAnalytics — single source of truth for survey-report data primitives.
#
# Both report pipelines (html_report's GenerateReportStructureJob / SurveyReportSemantics
# and the executive AiExecutiveReportJob) MUST go through here so the two never
# diverge again (option_ids matching, rating scale, %-parsing, cross-tab, themes,
# small-sample handling were previously duplicated and drifted apart, causing bugs).
#
# All methods are pure/stateless class methods.
module ReportAnalytics
  module_function

  # A cross-tab / distribution group with fewer than this many respondents is
  # statistically weak — we still show it but flag it as low-confidence.
  MIN_GROUP_N = 4

  TOOL_REGEX = /claude|chatgpt|gemini|gpt|cursor|copilot|codex|deepseek|midjourney|perplexity|antigravity|trae|kiro|kilo/i

  # ── JSONB option_ids matcher, robust to integer OR string storage ──────────
  def option_match(option_id)
    ["option_ids @> ? OR option_ids @> ?", [option_id.to_i].to_json, [option_id.to_s].to_json]
  end

  # ── Parse a percentage (1..100) out of free text ───────────────────────────
  def parse_pct(text)
    n = text.to_s.gsub(/[~≈≤≥\s%]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f
    (n && n > 0 && n <= 100) ? n : nil
  end

  # ── Derive the numeric scale from the DATA (never assume 1–5) ───────────────
  def numeric_max(nums, qtype, settings = nil)
    case qtype.to_s
    when "nps" then 10
    when "linear_scale"
      cfg = settings&.dig("max_value").to_i
      cfg.positive? ? cfg : [nums.map(&:round).max.to_i, 5].max
    else
      [nums.map(&:round).max.to_i, 5].max
    end
  end

  # ── Rating / NPS / linear_scale stats with a data-derived scale ─────────────
  # Returns { avg:, max:, total:, dist: [{ value:, count: }] }
  def rating_stats(nums, qtype, settings = nil)
    nums = Array(nums).map(&:to_f)
    maxv = numeric_max(nums, qtype, settings)
    start = qtype.to_s == "nps" ? 0 : 1
    {
      avg:   nums.any? ? (nums.sum / nums.size).round(2) : nil,
      max:   maxv,
      total: nums.size,
      dist:  (start..maxv).map { |v| { value: v, count: nums.count { |n| n.round == v } } }
    }
  end

  # ── Choice option counts for a question ────────────────────────────────────
  # Returns [{ id:, label:, count:, pct: }] (zero-count options dropped)
  def choice_counts(question, response_ids, denominator: nil)
    base  = Answer.where(question: question, response_id: response_ids)
    denom = denominator || base.count
    return [] if denom.zero?
    question.question_options.order(:position).filter_map do |opt|
      cnt = base.where(*option_match(opt.id)).count
      next if cnt.zero?
      { id: opt.id, label: opt.label, count: cnt, pct: (cnt.to_f / denom * 100).round(1) }
    end
  end

  # Tool aggregation already lives as a shared class method on SurveyReportSemantics.
  def aggregate_tools(texts, total) = SurveyReportSemantics.aggregate_tools(texts, total)

  # ── Near-unanimous (degenerate) choice? ─────────────────────────────────────
  # A single-answer question where ~everyone picked the same option has no
  # variance — better shown as a compact stat than a near-empty chart.
  DEGENERATE_PCT = 92

  def degenerate_choice?(options)
    opts = Array(options).reject { |o| (o[:count] || o["count"]).to_i.zero? }
    return false if opts.size > 1 && opts.none? { |o| (o[:pct] || o["pct"]).to_f >= DEGENERATE_PCT }
    opts.size == 1 || opts.any? { |o| (o[:pct] || o["pct"]).to_f >= DEGENERATE_PCT }
  end

  # ── Is a question a usable cross-tab TARGET? (quantitative only) ────────────
  # Choose-one / multi-select targets produce a meaningless "agreement %" bar.
  def quantitative_target?(question)
    %w[rating nps linear_scale short_text long_text].include?(question.question_type.to_s)
  end

  # ── Candidate grouping questions (dept/role/team/seniority…) ────────────────
  # Returns single_choice/dropdown questions with a small number of options,
  # preferring ones whose title looks like a segment dimension.
  GROUPING_TITLE = /\b(bộ phận|phòng ban|team|department|division|unit|vị trí|position|role|chức vụ|cấp bậc|seniority|level|nhóm|group|giới tính|gender|độ tuổi|age)\b/i

  def grouping_questions(questions)
    cand = questions.select do |q|
      q.question_type.to_s.in?(%w[single_choice dropdown]) &&
        q.question_options.size.between?(2, 12)
    end
    # Prefer title-matched segment dimensions, then any small single-choice
    named = cand.select { |q| q.title.to_s.match?(GROUPING_TITLE) }
    (named.presence || cand)
  end

  # ── Cross-tab: compare a quantitative target across the groups of a question ─
  # Returns nil if not meaningful, else:
  # { group_question:, target_type:, unit:, max:, groups: [{label:,value:,n:,low_confidence:}],
  #   low_confidence_overall: }  (groups sorted desc by value)
  def cross_tab(group_q, target_q, response_ids)
    return nil unless quantitative_target?(target_q)
    group_opts = group_q.question_options.order(:position)
    return nil if group_opts.empty?

    qtype = target_q.question_type.to_s
    pct_target = %w[short_text long_text].include?(qtype)
    settings   = target_q.settings

    groups = group_opts.filter_map do |opt|
      gids = Answer.where(question: group_q, response_id: response_ids)
                   .where(*option_match(opt.id)).pluck(:response_id)
      next if gids.empty?
      tbase = Answer.where(question: target_q, response_id: gids)

      value, n =
        if pct_target
          nums = tbase.where.not(text_value: [nil, ""]).pluck(:text_value).filter_map { |t| parse_pct(t) }
          [nums.any? ? (nums.sum / nums.size).round(1) : nil, nums.size]
        else
          nums = tbase.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f)
          [nums.any? ? (nums.sum / nums.size).round(1) : nil, nums.size]
        end
      next if value.nil? || n.zero?
      { label: opt.label.to_s.truncate(30), value: value, n: n, low_confidence: n < MIN_GROUP_N }
    end
    return nil if groups.empty?

    max_val = pct_target ? 100 :
              numeric_max(Answer.where(question: target_q, response_id: response_ids)
                                .where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f),
                          qtype, settings)
    {
      group_question:        group_q.title,
      target_type:           qtype,
      unit:                  pct_target ? "%" : "",
      max:                   max_val,
      groups:                groups.sort_by { |g| -g[:value] },
      low_confidence_overall: groups.all? { |g| g[:low_confidence] }
    }
  end

  # ── AI theme categorization (single implementation, no hardcoded domain rules) ─
  # Returns [{ "label" =>, "count" =>, "pct" => }] in the requested language.
  def categorize_themes(texts, question_title, total: nil, language: "vi")
    texts = Array(texts).map(&:to_s).reject(&:blank?)
    return [] if texts.size < 3
    total ||= texts.size
    lang_name = language == "vi" ? "Vietnamese (tiếng Việt)" : "English"
    sample = texts.first(40).map { |t| "- #{t.truncate(180)}" }.join("\n")

    system = "You are a survey analyst. Group open-ended responses into themes. " \
             "Return ONLY a JSON array, no markdown. Every \"label\" MUST be in #{lang_name}."
    user = <<~PROMPT
      Question: "#{question_title}"
      #{texts.size} text responses (out of #{total} respondents). Sample:
      #{sample}

      Group into 4–7 meaningful, non-overlapping themes grounded in the data.
      Each label: short (2–5 words) in #{lang_name}. Estimate count per theme (sum ≈ #{texts.size}).
      JSON: [{"label":"...","count":N},...] ordered by count desc.
    PROMPT

    raw   = ClaudeService.haiku.call(system_prompt: system, user_prompt: user, max_tokens: 600)
    clean = raw.to_s.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
    arr   = JSON.parse(clean[/\[.*\]/m] || "[]")
    arr.filter_map do |t|
      next if t["label"].blank? || t["count"].to_i <= 0
      cnt = t["count"].to_i
      { "label" => t["label"].to_s, "count" => cnt, "pct" => total > 0 ? (cnt.to_f / total * 100).round(1) : 0 }
    end.first(8)
  rescue => e
    Rails.logger.warn "[ReportAnalytics] categorize_themes failed: #{e.message}"
    []
  end
end
