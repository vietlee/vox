class GenerateReportStructureJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an expert survey data visualization & analysis designer.
    Given a survey's questions AND their actual aggregated response data, you will:
    1. Design the optimal visual report structure (sections + charts)
    2. Generate smart, data-backed insights and recommendations

    Respond ONLY with valid JSON — no markdown fences, no explanation.

    === CHART TYPES ===
    - "doughnut"              — single_choice/dropdown ≤8 options
    - "bar"                   — choice question >8 options OR any multi-select/tool question
    - "horizontal_bar"        — multiple_choice pain points / challenges
    - "distribution_bar"      — questions where answers are PERCENTAGES (savings, rates) — uses histogram buckets
    - "rating_bar"            — rating/linear_scale (horizontal bars, shows avg score)
    - "nps_bar"               — NPS 0–10 with colored bars (red=detractor, cyan=passive, green=promoter)
    - "quotes"                — long_text notable responses
    - "theme_bar"             — long_text suggestions → keyword-grouped bar
    - "number"                — single summary metric

    === PROCESSING HINTS ===
    - "normalize_tools"  — question asking which AI/software tools are used
    - "parse_percent"    — short_text where answer is a % number (savings, completion rate)
    - "extract_themes"   — long_text suggestions → group into themes

    === CROSS-TAB CARDS (question_id = null) ===
    Use when a grouping question (dept, role) + numeric/percent questions exist.
    Add as a card:
    {"question_id": null, "chart_type": "cross_tab_grouped_bar", "title": "...",
     "group_by_question_id": <dept_q_id>, "value_question_ids": [<id1>, <id2>],
     "processing": "parse_percent", "span": 12}

    === AI INSIGHTS ===
    Generate 2–5 data-backed insights. Two types:
    - type "stat": a key finding with exact numbers from the data
    - type "recommendation": an actionable step with title + rationale citing exact data

    === KPI SOURCES ===
    - "total_responses", "question_avg", "question_avg_pct", "question_top_option"

    === OUTPUT FORMAT ===
    {
      "kpis": [
        {"label": "...", "source": "total_responses", "color": "#4361ee"},
        {"label": "...", "source": "question_avg_pct", "question_id": 5, "color": "#06b6d4"}
      ],
      "sections": [
        {
          "id": "s1",
          "title": "Section title",
          "layout": "grid-2",
          "cards": [
            {"question_id": 2, "chart_type": "doughnut", "title": "Card title", "span": 6},
            {"question_id": 3, "chart_type": "bar", "processing": "normalize_tools", "title": "Card title", "span": 6},
            {"question_id": null, "chart_type": "cross_tab_grouped_bar", "title": "...",
             "group_by_question_id": 2, "value_question_ids": [5, 6], "processing": "parse_percent", "span": 12}
          ]
        }
      ],
      "ai_insights": [
        {"type": "stat", "text": "Exact number + what it means — cite the data"},
        {"type": "recommendation", "title": "Who does what by when", "detail": "Cite which question data led to this recommendation"}
      ]
    }

    Rules:
    - All text in same language as survey questions
    - span 6 = half width, span 12 = full width
    - distribution_bar/cross_tab/quotes → span 12 preferred; doughnut/bar → span 6
    - 2–6 sections, 2–5 cards per section
    - Every insight MUST reference actual numbers from the data provided
    - Recommendations must be specific: WHO + WHAT + concrete basis from data
  PROMPT

  def perform(survey_id)
    survey = Survey.find_by(id: survey_id)
    return unless survey

    questions = survey.questions.includes(:question_options).order(:position)
    return if questions.empty?

    # ── Step 1: Compute actual data from DB BEFORE calling AI ──────────────
    completed_ids = survey.responses.completed.where(excluded: [false, nil]).pluck(:id)
    data_summary  = build_data_summary(survey, questions, completed_ids)

    # ── Step 2: Build AI prompt with real data ──────────────────────────────
    questions_payload = questions.map.with_index do |q, i|
      {
        position: i + 1,
        id:       q.id,
        title:    q.title,
        type:     q.question_type,
        options:  q.question_options.order(:position).map(&:label).first(12)
      }
    end

    user_prompt = <<~MSG
      Survey: "#{survey.title}"
      #{survey.description.present? ? "Description: #{survey.description}" : ""}
      Total responses: #{completed_ids.size}

      ## ACTUAL RESPONSE DATA (computed from database — use these exact numbers):
      #{data_summary}

      ## Questions reference:
      #{JSON.pretty_generate(questions_payload)}

      Design the best visual report AND generate smart insights:
      - Use cross_tab_grouped_bar if there's a grouping question (dept/role) + numeric/percent questions
      - Use distribution_bar for any question asking "how much %" in free text
      - Use normalize_tools for questions asking which software/tools/AI are used
      - Use horizontal_bar for challenges/pain-points
      - Use theme_bar or quotes for open suggestions
      - Generate ai_insights with EXACT numbers from the data above
    MSG

    raw = ClaudeService.sonnet.call(
      system_prompt: SYSTEM_PROMPT,
      user_prompt:   user_prompt,
      max_tokens:    4000
    )

    # Strip markdown fences if present
    json_str  = raw.to_s.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    structure = JSON.parse(json_str)
    validate_structure!(structure, questions.map(&:id))

    settings = survey.settings.to_h.merge(
      "report_structure"         => structure,
      "report_structure_version" => Time.current.to_i.to_s
    )
    survey.update_columns(settings: settings)
    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} done — #{structure['sections']&.length} sections, #{structure['ai_insights']&.length} insights"

  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob JSON error survey #{survey_id}: #{e.message}\nRaw: #{raw.to_s.first(500)}"
    save_fallback_structure(survey)
  rescue => e
    Rails.logger.error "GenerateReportStructureJob error survey #{survey_id}: #{e.class} #{e.message}"
    save_fallback_structure(survey)
  end

  private

  # ── Compute actual aggregated data from DB ─────────────────────────────────
  def build_data_summary(survey, questions, completed_ids)
    return "No responses yet." if completed_ids.empty?

    lines = []
    questions.each_with_index do |q, i|
      pos  = i + 1
      base = Answer.where(question: q, response_id: completed_ids)
      n    = base.count
      next if n == 0

      line = "Q#{pos} (ID #{q.id}) [#{q.question_type}] #{q.title.truncate(70)}"

      case q.question_type.to_sym
      when :single_choice, :multiple_choice, :dropdown
        top_opts = q.question_options.order(:position).filter_map do |opt|
          cnt = base.where("option_ids @> ?", [opt.id.to_s].to_json).count
          cnt > 0 ? "#{opt.label}=#{cnt}(#{(cnt.to_f/n*100).round(1)}%)" : nil
        end.first(8)
        line += "\n  n=#{n}, options: #{top_opts.join(', ')}"

      when :rating, :nps, :linear_scale
        nums = base.where.not(numeric_value: nil).pluck(:numeric_value).map(&:to_f)
        if nums.any?
          avg = (nums.sum / nums.size).round(2)
          max_v = q.nps? ? 10 : (q.settings&.dig("max_value")&.to_i || 5)
          dist  = (q.nps? ? (0..10) : (1..max_v)).map { |v| c = nums.count{|n2| n2.round == v}; c > 0 ? "#{v}:#{c}" : nil }.compact
          line += "\n  n=#{nums.size}, avg=#{avg}/#{max_v}, dist=[#{dist.join(', ')}]"
        end

      when :short_text, :long_text
        texts = base.where.not(text_value: [nil, ""]).pluck(:text_value)
        if texts.any?
          nums = texts.filter_map { |t| t.gsub(/[~≈%\s]/, "").scan(/\d+(?:\.\d+)?/).first&.to_f }
                      .select { |v| v > 0 && v <= 100 }
          if nums.size >= texts.size * 0.4
            avg = (nums.sum / nums.size).round(1)
            line += "\n  n=#{texts.size}, numeric_pct: avg=#{avg}%, range=#{nums.min.round}–#{nums.max.round}%"
            buckets = [[0,19,"<20"],[20,39,"20-39"],[40,59,"40-59"],[60,79,"60-79"],[80,100,"80-100"]]
            dist_str = buckets.filter_map{|lo,hi,lbl| c=nums.count{|v|v>=lo&&v<=hi}; c>0 ? "#{lbl}%:#{c}" : nil}
            line += ", dist=[#{dist_str.join(', ')}]" if dist_str.any?
          else
            samples = texts.select{|t| t.length >= 20}.sample(3).map{|t| t.truncate(60)}
            line += "\n  n=#{texts.size}, samples: #{samples.inspect}"
          end
        end
      end
      lines << line
    end
    lines.join("\n\n")
  end

  def validate_structure!(structure, valid_ids)
    raise "Missing sections" unless structure["sections"].is_a?(Array)
    structure["sections"].each do |sec|
      sec["cards"]&.select! do |c|
        c["question_id"].nil? || valid_ids.include?(c["question_id"].to_i)
      end
      sec["cards"]&.each do |c|
        next unless c["chart_type"] == "cross_tab_grouped_bar"
        c["value_question_ids"] = Array(c["value_question_ids"]).map(&:to_i).select { |id| valid_ids.include?(id) }
      end
    end
    structure["sections"].reject! { |s| s["cards"].blank? }
    structure["kpis"]&.select! do |kpi|
      kpi["source"] == "total_responses" || valid_ids.include?(kpi["question_id"].to_i)
    end
    # Ensure ai_insights is an array
    structure["ai_insights"] = Array(structure["ai_insights"]).select { |i| i["text"].present? || i["title"].present? }
  end

  def save_fallback_structure(survey)
    return unless survey
    questions = survey.questions.includes(:question_options).order(:position)
    groups    = questions.group_by { |q|
      case q.question_type
      when "single_choice", "multiple_choice", "dropdown" then "choice"
      when "rating", "linear_scale", "nps"                then "numeric"
      else "text"
      end
    }
    sections = []
    titles   = { "choice" => "Câu hỏi lựa chọn", "numeric" => "Đánh giá & chỉ số", "text" => "Phản hồi tự do" }
    groups.each_with_index do |(type, qs), i|
      cards = qs.map do |q|
        ct = case q.question_type
             when "single_choice", "dropdown" then "doughnut"
             when "multiple_choice"            then "horizontal_bar"
             when "nps"                        then "nps_bar"
             when "rating", "linear_scale"     then "rating_bar"
             else "quotes"
             end
        span = %w[short_text long_text].include?(q.question_type) ? 12 : 6
        { "question_id" => q.id, "chart_type" => ct, "title" => q.title.truncate(60), "span" => span }
      end
      sections << { "id" => "s#{i+1}", "title" => titles[type] || "Câu hỏi", "layout" => "grid-2", "cards" => cards }
    end
    kpis = [{ "label" => "Người tham gia", "source" => "total_responses", "color" => "#4361ee" }]
    structure = { "kpis" => kpis, "sections" => sections, "ai_insights" => [], "_fallback" => true }
    survey.update_columns(settings: survey.settings.to_h.merge("report_structure" => structure,
                                                                "report_structure_version" => Time.current.to_i.to_s))
  end
end
