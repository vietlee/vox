class GenerateReportStructureJob < ApplicationJob
  queue_as :default

  INSIGHTS_SYSTEM_PROMPT = <<~PROMPT.freeze
    Bạn là chuyên gia phân tích dữ liệu khảo sát. Nhiệm vụ duy nhất của bạn là sinh ra
    các insights thông minh, súc tích dựa trên dữ liệu thực. Chỉ trả về JSON array thuần túy.
  PROMPT

  # Legacy — kept for reference but no longer used for structure generation
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

    completed_ids = survey.responses.completed.where(excluded: [false, nil]).pluck(:id)

    # ── Step 1: Ruby semantic detection builds structure deterministically ──
    semantics_builder = SurveyReportSemantics.new(survey, completed_ids)
    structure         = semantics_builder.build_structure
    data_summary      = semantics_builder.data_summary_for_ai

    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} — Ruby built #{structure['sections']&.length} sections, now calling AI for insights"

    # ── Step 2: AI generates ONLY insights (not structure) ─────────────────
    insights_prompt = <<~MSG
      Survey: "#{survey.title}"
      #{survey.description.present? ? "Mô tả: #{survey.description}" : ""}
      Tổng số phản hồi: #{completed_ids.size}

      ## Dữ liệu thực từ database:
      #{data_summary}

      Dựa trên tiêu đề, mô tả và dữ liệu khảo sát trên, hãy sinh ra 4–6 insights thông minh.
      Hai loại:
      - type "stat": phát hiện quan trọng có số liệu cụ thể (ví dụ: "78% nhân viên Frontend tiết kiệm trên 60% thời gian")
      - type "recommendation": đề xuất hành động cụ thể với WHO + WHAT + số liệu dẫn chứng

      Trả về JSON array (chỉ array, không có wrapper):
      [
        {"type": "stat", "text": "..."},
        {"type": "recommendation", "title": "...", "detail": "..."}
      ]

      Quan trọng: dùng đúng ngôn ngữ của survey, trích dẫn số liệu thực từ dữ liệu.
    MSG

    raw      = ClaudeService.sonnet.call(system_prompt: INSIGHTS_SYSTEM_PROMPT,
                                         user_prompt:   insights_prompt, max_tokens: 2000)
    json_str = raw.to_s.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    insights = JSON.parse(json_str)
    insights = insights["ai_insights"] if insights.is_a?(Hash) # unwrap if AI wrapped it
    structure["ai_insights"] = Array(insights).select { |i| i["text"].present? || i["title"].present? }

    settings = survey.settings.to_h.merge(
      "report_structure"         => structure,
      "report_structure_version" => Time.current.to_i.to_s
    )
    survey.update_columns(settings: settings)
    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} done — #{structure['sections']&.length} sections, #{structure['ai_insights']&.length} insights"

  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob JSON error survey #{survey_id}: #{e.message}\nRaw: #{raw.to_s.first(500)}"
    # Save structure without insights rather than full fallback
    if defined?(structure) && structure["sections"].present?
      structure["ai_insights"] = []
      survey.update_columns(settings: survey.settings.to_h.merge("report_structure" => structure,
                                                                   "report_structure_version" => Time.current.to_i.to_s))
    else
      save_fallback_structure(survey)
    end
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
