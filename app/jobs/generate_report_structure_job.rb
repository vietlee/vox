class GenerateReportStructureJob < ApplicationJob
  queue_as :default

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are an expert survey report designer. Given a list of survey questions, your job is to:
    1. Group questions into meaningful thematic sections
    2. Choose the best chart type for each question
    3. Identify which questions should be KPIs in the header

    Respond ONLY with valid JSON. No explanation, no markdown, no code fences.

    Rules:
    - Group questions by semantic theme (demographics, satisfaction, usage, challenges, etc.)
    - 1 section = 2–5 related questions, max 8 sections total
    - chart_type options: "doughnut" (choice ≤6 options), "bar" (choice >6 or many options), "rating_bar" (rating/scale/nps), "quotes" (text/open-ended), "number" (single numeric)
    - span: 6 = half width, 12 = full width (use 12 for text/quotes or questions with many options >8)
    - layout: "grid-2" (default, 2 columns) or "grid-3" (3 columns, only if section has 3+ short charts)
    - kpis: pick 2–4 most impactful metrics. source can be "total_responses" or "question_avg" (for rating/nps questions) or "question_top_option" (most chosen option)
    - All section titles and KPI labels must be in the same language as the survey questions

    Output format:
    {
      "kpis": [
        {"label": "Label text", "source": "total_responses", "color": "#4361ee"},
        {"label": "Label text", "source": "question_avg", "question_id": 123, "color": "#10b981"},
        {"label": "Label text", "source": "question_top_option", "question_id": 124, "color": "#f59e0b"}
      ],
      "sections": [
        {
          "id": "s1",
          "title": "Section title",
          "layout": "grid-2",
          "cards": [
            {"question_id": 1, "chart_type": "doughnut", "span": 6},
            {"question_id": 2, "chart_type": "bar", "span": 6}
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
        options: q.question_options.order(:position).map(&:label)
      }
    end

    user_prompt = "Survey: \"#{survey.title}\"\n\nQuestions:\n#{JSON.pretty_generate(questions_payload)}"

    raw = ClaudeService.haiku.call(
      system_prompt: SYSTEM_PROMPT,
      user_prompt:   user_prompt,
      max_tokens:    2048
    )

    structure = JSON.parse(raw)
    validate_structure!(structure, questions.map(&:id))

    settings = survey.settings.to_h.merge("report_structure" => structure)
    survey.update_columns(settings: settings)

    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} structure saved (#{structure['sections']&.length} sections)"
  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob: JSON parse error for survey #{survey_id}: #{e.message}"
    save_fallback_structure(survey)
  rescue => e
    Rails.logger.error "GenerateReportStructureJob: error for survey #{survey_id}: #{e.message}"
    save_fallback_structure(survey)
  end

  private

  # Ensure all question_ids in structure exist in this survey
  def validate_structure!(structure, valid_ids)
    raise "Missing sections" unless structure["sections"].is_a?(Array)
    structure["sections"].each do |sec|
      sec["cards"]&.select! { |c| valid_ids.include?(c["question_id"].to_i) }
    end
    structure["sections"].reject! { |s| s["cards"].blank? }
    structure["kpis"]&.select! do |kpi|
      kpi["source"] == "total_responses" || valid_ids.include?(kpi["question_id"].to_i)
    end
  end

  # Fallback: 1 section per question type group if AI fails
  def save_fallback_structure(survey)
    return unless survey

    questions = survey.questions.includes(:question_options).order(:position)
    groups = questions.group_by { |q|
      if %w[single_choice multiple_choice dropdown].include?(q.question_type)
        "choice"
      elsif %w[rating linear_scale nps].include?(q.question_type)
        "numeric"
      else
        "text"
      end
    }

    sections = []
    group_titles = { "choice" => "Câu hỏi lựa chọn", "numeric" => "Đánh giá & chỉ số", "text" => "Phản hồi tự do" }
    groups.each_with_index do |(type, qs), i|
      cards = qs.map do |q|
        chart_type = case q.question_type
          when "single_choice", "dropdown" then qs.size <= 6 ? "doughnut" : "bar"
          when "multiple_choice" then "bar"
          when "rating", "linear_scale", "nps" then "rating_bar"
          else "quotes"
        end
        span = %w[short_text long_text].include?(q.question_type) ? 12 : 6
        { "question_id" => q.id, "chart_type" => chart_type, "span" => span }
      end
      sections << { "id" => "s#{i+1}", "title" => group_titles[type] || "Câu hỏi", "layout" => "grid-2", "cards" => cards }
    end

    kpis = [{ "label" => "Người tham gia", "source" => "total_responses", "color" => "#4361ee" }]
    nps_q = questions.find { |q| q.question_type == "nps" }
    kpis << { "label" => "Điểm NPS TB", "source" => "question_avg", "question_id" => nps_q.id, "color" => "#f59e0b" } if nps_q

    structure = { "kpis" => kpis, "sections" => sections, "_fallback" => true }
    settings  = survey.settings.to_h.merge("report_structure" => structure)
    survey.update_columns(settings: settings)
  end
end
