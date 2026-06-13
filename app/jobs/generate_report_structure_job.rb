class GenerateReportStructureJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an expert survey data visualization designer. Given survey questions, design the optimal visual report structure.

    Respond ONLY with valid JSON — no markdown, no explanation.

    === CHART TYPES ===
    - "doughnut"              — choice question ≤8 options → pie/donut chart
    - "bar"                   — choice question >8 options OR tool/multi-select → vertical bar
    - "horizontal_bar"        — multiple_choice for pain points / challenges (horizontal easier to read)
    - "distribution_bar"      — short_text where answers are PERCENTAGES (e.g. "Bạn tiết kiệm bao % thời gian?") → histogram by bucket
    - "rating_bar"            — rating/linear_scale questions → horizontal bars with avg score
    - "nps_bar"               — NPS (0-10) question → colored bar chart (red=detractor, cyan=passive, green=promoter)
    - "quotes"                — long_text / open-ended → notable quote cards
    - "theme_bar"             — long_text asking for suggestions/recommendations → auto-group by keyword themes
    - "number"                — single numeric summary

    === PROCESSING HINTS (add "processing" key when applicable) ===
    - "normalize_tools"       — free-text question asking WHICH AI tools/software used → normalize & aggregate tool names
    - "parse_percent"         — short_text where answer is a % number (savings, completion rate, etc.)
    - "extract_themes"        — long_text suggestions → keyword-group into themes

    === CROSS-TAB CARDS (special: no question_id, placed at end of a section) ===
    Use when there is a GROUPING question (department, role, team) AND one or more numeric questions
    that can be broken down by group. Add as a card with question_id = null:
    {
      "question_id": null,
      "chart_type": "cross_tab_grouped_bar",
      "title": "Cross-tab title",
      "group_by_question_id": <id of dept/role question>,
      "value_question_ids": [<id1>, <id2>],
      "processing": "parse_percent",
      "span": 12
    }

    === KPI SOURCES ===
    - "total_responses"       — total count
    - "question_avg"          — numeric average of a rating/NPS question
    - "question_avg_pct"      — average of a parse_percent question (shown as %)
    - "question_top_option"   — most selected option label

    === LAYOUT RULES ===
    - span 6 = half width, span 12 = full width
    - layout "grid-2" (default), "grid-3" (only for 3+ short charts)
    - distribution_bar: span 6; cross_tab: span 12; quotes: span 12; theme_bar: span 6 or 12
    - 2–5 questions per section, max 7 sections
    - All text in same language as survey questions

    === OUTPUT FORMAT ===
    {
      "kpis": [
        {"label": "...", "source": "total_responses", "color": "#4361ee"},
        {"label": "...", "source": "question_avg_pct", "question_id": 5, "color": "#06b6d4"},
        {"label": "...", "source": "question_avg", "question_id": 8, "color": "#f59e0b"}
      ],
      "sections": [
        {
          "id": "s1",
          "title": "Section title",
          "layout": "grid-2",
          "cards": [
            {"question_id": 2, "chart_type": "doughnut", "title": "Card title", "span": 6},
            {"question_id": 3, "chart_type": "bar", "title": "Card title", "processing": "normalize_tools", "span": 6},
            {"question_id": null, "chart_type": "cross_tab_grouped_bar", "title": "Cross-tab title",
             "group_by_question_id": 2, "value_question_ids": [5, 6], "processing": "parse_percent", "span": 12}
          ]
        }
      ]
    }
  PROMPT

  def perform(survey_id)
    survey = Survey.find_by(id: survey_id)
    return unless survey

    questions = survey.questions.includes(:question_options).order(:position)
    return if questions.empty?

    questions_payload = questions.map do |q|
      {
        id:      q.id,
        title:   q.title,
        type:    q.question_type,
        options: q.question_options.order(:position).map(&:label).first(12)
      }
    end

    user_prompt = <<~MSG
      Survey: "#{survey.title}"

      Questions:
      #{JSON.pretty_generate(questions_payload)}

      Design the best visual report. Use cross-tab if there's a grouping question + numeric/percent questions.
      Use distribution_bar for any question asking "how much %" in free text.
      Use normalize_tools for any question asking which software/tools/AI are used.
      Use horizontal_bar for challenges/pain-points.
      Use theme_bar or quotes for open suggestions.
    MSG

    raw = ClaudeService.haiku.call(
      system_prompt: SYSTEM_PROMPT,
      user_prompt:   user_prompt,
      max_tokens:    3000
    )

    # Strip markdown code fences if present
    json_str = raw.to_s.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    structure = JSON.parse(json_str)
    validate_structure!(structure, questions.map(&:id))

    settings = survey.settings.to_h.merge(
      "report_structure"         => structure,
      "report_structure_version" => Time.current.to_i.to_s
    )
    survey.update_columns(settings: settings)
    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} done (#{structure['sections']&.length} sections)"

  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob JSON error survey #{survey_id}: #{e.message}\nRaw: #{raw.to_s.first(500)}"
    save_fallback_structure(survey)
  rescue => e
    Rails.logger.error "GenerateReportStructureJob error survey #{survey_id}: #{e.message}"
    save_fallback_structure(survey)
  end

  private

  def validate_structure!(structure, valid_ids)
    raise "Missing sections" unless structure["sections"].is_a?(Array)
    structure["sections"].each do |sec|
      sec["cards"]&.select! do |c|
        c["question_id"].nil? || valid_ids.include?(c["question_id"].to_i)
      end
      # Validate cross-tab references
      sec["cards"]&.each do |c|
        next unless c["chart_type"] == "cross_tab_grouped_bar"
        c["value_question_ids"] = Array(c["value_question_ids"]).map(&:to_i).select { |id| valid_ids.include?(id) }
      end
    end
    structure["sections"].reject! { |s| s["cards"].blank? }
    structure["kpis"]&.select! do |kpi|
      kpi["source"] == "total_responses" || valid_ids.include?(kpi["question_id"].to_i)
    end
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
    structure = { "kpis" => kpis, "sections" => sections, "_fallback" => true,
                  "report_structure_version" => Time.current.to_i.to_s }
    survey.update_columns(settings: survey.settings.to_h.merge("report_structure" => structure,
                                                                "report_structure_version" => Time.current.to_i.to_s))
  end
end
