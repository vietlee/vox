require "net/http"

class AiSurveyAnalysisJob < ApplicationJob
  queue_as :ai

  TRANSIENT_ERRORS = [Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT].freeze

  retry_on(*TRANSIENT_ERRORS, wait: 20.seconds, attempts: 2) do |job_instance, error|
    ai_job = AiJob.find_by(id: job_instance.arguments.first)
    ai_job&.fail!("Network timeout after retries: #{error.message.truncate(200)}")
  end

  def perform(job_id)
    job    = AiJob.find(job_id)
    survey = Survey.find(job.resource_id)
    job.start!

    responses = survey.responses.completed.includes(answers: :question)
    return job.complete!({ error: "no_data" }) if responses.empty?

    language  = job.input_data&.dig("language") || survey.workspace.language || "vi"
    lang_name = language == "vi" ? "Vietnamese" : "English"

    # ─── LAYER 1: Deterministic calculator ───────────────────────────────
    # All numbers are computed in Ruby — AI will only read, never recalculate
    completed_ids = responses.map(&:id)
    computed      = build_computed_stats(survey, responses)
    open_texts    = build_open_text_data(survey, responses)
    structured    = computed[:structured_data]
    global_stats  = computed[:global_stats]
    cross_tabs    = build_cross_tab_stats(survey, completed_ids, structured)

    system_prompt = <<~SYSTEM
      You are a senior analyst writing executive-ready survey insights.
      Write entirely in #{lang_name}. Be direct, specific, and actionable.

      CRITICAL DATA RULES — violations corrupt the report:
      1. ALL percentages and counts MUST come from the "structured_data" JSON. Never compute or estimate numbers yourself.
      2. When citing a percentage, it must EXACTLY match a value in the data (e.g. if data says 47.8%, write 47.8% — not "nearly half" without the number).
      3. For open-text questions: identify themes and cite representative quotes. Do NOT assign percentages to themes.
      4. NPS/satisfaction scoring: use the pre-computed nps_breakdown in the data — do not reclassify respondents.
      5. If a subgroup has low_sample: true (n < 3), note "cỡ mẫu nhỏ" — do not draw conclusions from it.
      6. Return ONLY valid JSON. Use \\n\\n for paragraph breaks. No markdown fences.
    SYSTEM

    user_prompt = <<~PROMPT
      Analyze this survey data and write insights. All numbers are pre-computed — use them exactly.

      ## Survey
      Title: #{survey.title}
      #{survey.description.present? ? "Purpose: #{survey.description}" : ""}
      Responses: #{responses.count}#{responses.count < 10 ? " ⚠️ small sample — be cautious with conclusions" : ""}

      ## Pre-computed Stats (source of truth — cite these numbers directly)
      #{global_stats.to_json}

      ## Question Data (structured)
      #{structured.to_json.truncate(6000)}

      #{cross_tabs.any? ? "## Cross-tab Breakdowns (outcome metrics broken down by grouping questions — USE THESE for subgroup analysis)\n#{cross_tabs.to_json.truncate(3000)}" : ""}

      #{open_texts.any? ? "## Open-text Responses (qualitative only — do NOT assign counts or %)\n#{open_texts.to_json.truncate(2000)}" : ""}

      ## Required JSON output (ALL text in #{lang_name}):
      {
        "executive_summary": "3 paragraphs, each DIFFERENT — never repeat. Use \\n\\n between paragraphs.\\nPara 1 (HEADLINE): The most important finding with its exact number. If questions have subtype='pct', they ARE the survey's core metric — lead with their avg and the biggest subgroup gap from the cross-tab data (e.g. 'Bộ phận X tiết kiệm 70% vs Bộ phận Y chỉ 40%').\\nPara 2 (PATTERNS): What do 2+ questions together reveal that no single question shows alone?\\nPara 3 (ACTION): Who should do what by when, and why now?",

        "key_metrics": {
          "response_count": #{responses.count},
          "overall_avg": #{global_stats[:overall_numeric_avg] || "null"},
          "standout_high": "question with best result — cite exact score from data",
          "standout_low": "question with worst result — cite exact score from data",
          "data_quality": "#{responses.count < 10 ? "small sample — interpret with caution" : "reliable"}"
        },

        "sentiment": {
          "positive": "#{global_stats[:sentiment_positive]}%",
          "neutral": "#{global_stats[:sentiment_neutral]}%",
          "negative": "#{global_stats[:sentiment_negative]}%",
          "sentiment_note": "one sentence interpreting the sentiment pattern shown by the numeric data"
        },

        "question_insights": [
          {
            "question_id": <integer id from data>,
            "question": "question title",
            "finding": "key finding — MUST cite exact number from structured_data (e.g. 'X% chose Y', 'mean = Z')",
            "concern_level": "high|medium|low"
          }
        ],

        "open_text_themes": [
          {
            "theme": "theme name",
            "representative_quotes": ["quote 1", "quote 2"],
            "sentiment": "positive|neutral|negative",
            "question_id": <integer>
          }
        ],

        "anomalies": ["Specific outlier with exact data to back it up"],

        "highlights": ["Specific positive finding with exact percentage or score from data"],

        "recommendations": [
          {
            "action": "Specific action — who does what by when",
            "rationale": "Why — cite specific question ID and finding",
            "impact": "Expected outcome",
            "priority": "high|medium|low"
          }
        ]
      }

      Rules:
      - question_insights: one entry per structured question with meaningful data. question_id must be the integer ID from the data.
      - open_text_themes: only for short_text/long_text questions. 2-4 themes max per question.
      - recommendations: 3-5 items, ordered by priority. Each must cite a specific question ID.
      - sentiment values are PRE-FILLED above — copy them exactly into the output.
    PROMPT

    result_text = ClaudeService.opus_long.call(
      system_prompt: system_prompt,
      user_prompt:   user_prompt,
      max_tokens:    8000
    )

    result = parse_json_response(result_text)

    # ─── LAYER 3: Validation — enforce pre-computed numbers ──────────────
    result["sentiment"] = {
      "positive"      => "#{global_stats[:sentiment_positive]}%",
      "neutral"       => "#{global_stats[:sentiment_neutral]}%",
      "negative"      => "#{global_stats[:sentiment_negative]}%",
      "sentiment_note"=> result.dig("sentiment", "sentiment_note") || ""
    }
    result["key_metrics"]&.merge!(
      "response_count" => responses.count,
      "overall_avg"    => global_stats[:overall_numeric_avg]
    )

    # Attach pre-computed data for UI rendering
    result["_computed"] = {
      "structured_data" => structured,
      "global_stats"    => global_stats,
      "open_text_data"  => open_texts
    }

    AiAnalysisResult.create!(
      workspace:      job.workspace,
      ai_job:         job,
      result_type:    "executive_summary",
      resource_type:  "Survey",
      resource_id:    survey.id,
      output:         result,
      credits_cost:   job.credits_cost,
      response_count: responses.count
    )

    job.complete!(result)
  rescue => e
    if TRANSIENT_ERRORS.any? { |klass| e.is_a?(klass) }
      raise
    else
      job.fail!(e.message)
    end
  end

  private

  # ─── LAYER 1: All deterministic computations ─────────────────────────────
  def build_computed_stats(survey, responses)
    completed_ids  = responses.map(&:id)
    structured     = []
    numeric_avgs   = []
    all_numeric_answers = []

    survey.questions.order(:position).includes(:question_options).each do |q|
      answers = Answer.where(question: q, response_id: completed_ids)
      next if answers.empty?

      entry = { question_id: q.id, question: q.title, type: q.question_type, total: answers.count }

      case q.question_type
      when "linear_scale", "nps", "rating"
        nums = answers.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_i)
        next if nums.empty?
        sorted = nums.sort
        max_val = q.nps? ? 10 : (q.settings&.dig("max_value")&.to_i || 5)
        avg = (nums.sum.to_f / nums.size).round(2)
        numeric_avgs << avg
        all_numeric_answers.concat(nums.map { |v| { value: v, max: max_val } })

        dist = (0..max_val).map { |v| { value: v, count: nums.count(v), pct: (nums.count(v).to_f / nums.size * 100).round(1) } }
               .reject { |d| d[:count] == 0 && d[:value] < 1 }

        entry.merge!(
          answered:     nums.size,
          mean:         avg,
          median:       sorted[sorted.size / 2],
          min:          sorted.first,
          max_val:      max_val,
          distribution: dist
        )

        # NPS-specific breakdown (Hài lòng cao / Trung lập / Không hài lòng)
        if q.nps?
          promoters  = nums.count { |v| v >= 9 }
          passives   = nums.count { |v| v >= 7 && v <= 8 }
          detractors = nums.count { |v| v <= 6 }
          nps_score  = ((promoters - detractors).to_f / nums.size * 100).round(1)
          entry[:nps_breakdown] = {
            hai_long_cao:    { count: promoters,  pct: (promoters.to_f  / nums.size * 100).round(1) },
            trung_lap:       { count: passives,   pct: (passives.to_f   / nums.size * 100).round(1) },
            khong_hai_long:  { count: detractors, pct: (detractors.to_f / nums.size * 100).round(1) },
            do_hai_long_score: nps_score
          }
        end

      when "single_choice", "multiple_choice", "dropdown", "checkbox"
        # Fix: option_ids stores string IDs — must look up by string key
        option_labels = q.question_options.index_by { |o| o.id.to_s }
        counts = Hash.new(0)
        answers.each { |a| (a.option_ids || []).each { |oid| counts[oid.to_s] += 1 } }

        total_selections = q.question_type.in?(%w[multiple_choice checkbox]) ? counts.values.sum : answers.count
        base_n = answers.count

        options = q.question_options.order(:position).map do |opt|
          cnt = counts[opt.id.to_s]
          pct = base_n > 0 ? (cnt.to_f / base_n * 100).round(1) : 0
          low_sample = base_n < 3
          { option_id: opt.id, label: opt.label, count: cnt, pct: pct, low_sample: low_sample }
        end.reject { |o| o[:count] == 0 && q.question_options.count > 5 }

        entry.merge!(answered: base_n, options: options)

      when "short_text", "long_text"
        # Detect numeric-percentage answers (e.g. "50%", "70") — treat as quantitative
        texts = answers.where.not(text_value: [nil, ""]).pluck(:text_value)
        next if texts.empty?
        nums = texts.filter_map { |t|
          t.to_s.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f
        }.select { |n| n > 0 && n <= 100 }

        if nums.size >= texts.size * 0.5
          # Majority numeric → treat as a percentage scale question
          avg  = (nums.sum / nums.size).round(1)
          dist = [[0,20],[21,40],[41,60],[61,80],[81,100]].map do |lo, hi|
            cnt = nums.count { |n| n >= lo && n <= hi }
            { range: "#{lo}–#{hi}%", count: cnt, pct: (cnt.to_f / nums.size * 100).round(1) }
          end
          numeric_avgs << avg
          all_numeric_answers.concat(nums.map { |v| { value: v, max: 100 } })
          entry.merge!(
            subtype:      "pct",
            answered:     nums.size,
            mean:         avg,
            max_val:      100,
            distribution: dist,
            note:         "Câu trả lời dạng % — được xử lý như thang đo định lượng"
          )
        else
          next  # Pure text — handled by open_text_data
        end
      end

      structured << entry
    end

    # Global numeric stats for sentiment pre-computation
    global_avg = numeric_avgs.any? ? (numeric_avgs.sum / numeric_avgs.size).round(2) : nil

    # Compute sentiment from numeric answers (above midpoint = positive, below = negative)
    if all_numeric_answers.any?
      positive_count  = all_numeric_answers.count { |a| a[:value].to_f / a[:max] >= 0.7 }
      neutral_count   = all_numeric_answers.count { |a| r = a[:value].to_f / a[:max]; r >= 0.4 && r < 0.7 }
      negative_count  = all_numeric_answers.count { |a| a[:value].to_f / a[:max] < 0.4 }
      total_ans       = all_numeric_answers.size
      sentiment_pos   = (positive_count.to_f  / total_ans * 100).round(1)
      sentiment_neu   = (neutral_count.to_f   / total_ans * 100).round(1)
      sentiment_neg   = (negative_count.to_f  / total_ans * 100).round(1)
    else
      sentiment_pos = sentiment_neu = sentiment_neg = nil
    end

    global_stats = {
      overall_numeric_avg: global_avg,
      sentiment_positive:  sentiment_pos,
      sentiment_neutral:   sentiment_neu,
      sentiment_negative:  sentiment_neg,
      response_count:      responses.count,
      low_sample_warning:  responses.count < 10
    }

    { structured_data: structured, global_stats: global_stats }
  end

  # Build cross-tab: for every grouping variable (single_choice/dropdown),
  # compute avg of each numeric outcome question broken down by group option.
  def build_cross_tab_stats(survey, completed_ids, structured)
    return [] if completed_ids.empty?

    # Identify grouping questions (demographic/segmentation variables)
    group_questions = survey.questions.includes(:question_options)
                            .where(question_type: %w[single_choice dropdown])
                            .order(:position)
    return [] if group_questions.empty?

    # Identify numeric outcome questions from structured data
    numeric_entries = structured.select { |e|
      %w[rating linear_scale nps].include?(e[:type]) ||
        (e[:type].in?(%w[short_text long_text]) && e[:subtype] == "pct")
    }
    return [] if numeric_entries.empty?

    results = []

    group_questions.each do |gq|
      groups = gq.question_options.order(:position).map do |opt|
        # Response IDs where respondent chose this option
        resp_ids = Answer.where(question: gq, response_id: completed_ids)
                         .where("option_ids @> ?", [opt.id.to_s].to_json)
                         .pluck(:response_id)
        next if resp_ids.empty?
        { option_id: opt.id, label: opt.label, response_ids: resp_ids }
      end.compact
      next if groups.empty?

      numeric_entries.each do |entry|
        target_q = survey.questions.find_by(id: entry[:question_id])
        next unless target_q

        group_avgs = groups.map do |grp|
          base = Answer.where(question: target_q, response_id: grp[:response_ids])

          nums = if target_q.question_type.in?(%w[short_text long_text])
            base.where.not(text_value: [nil, ""])
                .pluck(:text_value)
                .filter_map { |t| t.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                .select { |n| n > 0 && n <= 100 }
          else
            base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f)
          end

          next if nums.empty?
          avg = (nums.sum / nums.size).round(1)
          { group: grp[:label], avg: avg, n: nums.size,
            low_sample: nums.size < 3 }
        end.compact

        next if group_avgs.size < 2  # need at least 2 groups to compare

        avgs_only = group_avgs.reject { |g| g[:low_sample] }.map { |g| g[:avg] }
        gap = avgs_only.any? ? (avgs_only.max - avgs_only.min).round(1) : nil

        results << {
          target_question_id:   target_q.id,
          target_question:      target_q.title.truncate(60),
          group_by_question_id: gq.id,
          group_by_question:    gq.title.truncate(40),
          groups:               group_avgs,
          gap_between_groups:   gap,
          insight_flag:         gap && gap >= 15 ? "large_gap" : nil
        }
      end
    end

    results
  end

  def build_open_text_data(survey, responses)
    completed_ids = responses.map(&:id)
    survey.questions.order(:position)
          .select { |q| %w[short_text long_text].include?(q.question_type) }
          .filter_map do |q|
            texts = Answer.where(question: q, response_id: completed_ids)
                          .where.not(text_value: [nil, ""])
                          .pluck(:text_value)
                          .map { |t| t.gsub('"', "'").gsub(/[\x00-\x1F]/, " ").strip.truncate(300) }
                          .reject(&:blank?)
            next if texts.empty?

            # Skip if majority numeric — already handled in build_computed_stats as quantitative data
            nums = texts.filter_map { |t| t.gsub(/[~≈]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }.select { |n| n > 0 && n <= 100 }
            next if nums.size >= texts.size * 0.5

            { question_id: q.id, question: q.title, response_count: texts.count, responses: texts.first(20) }
          end
  end

  def parse_json_response(text)
    clean    = text.gsub(/\A\s*```(?:json)?\s*/i, '').gsub(/\s*```\s*\z/, '').strip
    json_str = clean.match(/\{.*\}/m)&.to_s || clean
    begin
      return JSON.parse(json_str)
    rescue JSON::ParserError
    end
    begin
      return JSON.parse(fix_json_strings(json_str))
    rescue JSON::ParserError
    end
    begin
      return JSON.parse(json_str.gsub(/[\x00-\x1F\x7F]/, ''))
    rescue JSON::ParserError
    end
    begin
      return JSON.parse(repair_truncated_json(json_str))
    rescue JSON::ParserError => e
      raise "JSON parse failed: #{e.message.truncate(200)}"
    end
  end

  def repair_truncated_json(s)
    repaired = s.gsub(/,\s*\z/, '').gsub(/,\s*"[^"]*"\s*:\s*[^,}\]]*\z/, '')
    depth_obj = 0; depth_arr = 0; in_str = false; i = 0
    while i < repaired.length
      c = repaired[i]
      if in_str
        in_str = false if c == '"' && repaired[i-1] != '\\'
      else
        case c
        when '"' then in_str = true
        when '{' then depth_obj += 1
        when '}' then depth_obj -= 1
        when '[' then depth_arr += 1
        when ']' then depth_arr -= 1
        end
      end
      i += 1
    end
    repaired + (']' * [depth_arr, 0].max) + ('}' * [depth_obj, 0].max)
  end

  def fix_json_strings(s)
    out = String.new(encoding: "UTF-8")
    in_str = false; i = 0
    while i < s.length
      c = s[i]
      if in_str
        case c
        when "\\" then out << c << (s[i + 1] || ""); i += 2; next
        when '"'  then in_str = false; out << c
        when "\n" then out << '\\n'
        when "\r" then out << '\\r'
        when "\t" then out << '\\t'
        else out << c
        end
      else
        out << c
        in_str = true if c == '"'
      end
      i += 1
    end
    out
  end
end
