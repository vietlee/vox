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

  def perform(survey_id, language = "vi")
    language = language.presence_in(%w[vi en]) || "vi"
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

    # ── Step 2: AI shortens labels + generates insights ───────────────────
    # Collect all texts needing shortening
    kpi_texts = structure["kpis"].map { |k| k["label"] }

    section_titles = structure["sections"].map { |s| s["title"] }

    card_texts = structure["sections"].flat_map { |s|
      s["cards"].map { |c| c["title"].to_s }
    }

    output_lang     = language == "vi" ? "Vietnamese (tiếng Việt)" : "English"
    task1_label     = language == "vi" ? "Rút gọn nhãn KPI (tối đa 4 từ, súc tích)" : "Shorten KPI labels (max 4 words, clear)"
    task2_label     = language == "vi" ? "Rút gọn tiêu đề section (tối đa 5 từ, rõ ý)" : "Shorten section titles (max 5 words, clear)"
    task3_label     = language == "vi" ? "Rút gọn tiêu đề card/chart (tối đa 6 từ)" : "Shorten chart titles (max 6 words)"
    task4_label     = language == "vi" ? "Insights thông minh (4–6 insights)" : "Smart insights (4–6 insights)"
    stat_desc       = language == "vi" ? "phát hiện quan trọng với số liệu cụ thể" : "key finding with specific data"
    rec_desc        = language == "vi" ? "đề xuất hành động WHO + WHAT + dẫn chứng số liệu" : "action recommendation WHO + WHAT + data evidence"
    return_label    = language == "vi" ? "Trả về JSON (không markdown):" : "Return JSON (no markdown):"

    insights_prompt = <<~MSG
      ⚠️ LANGUAGE RULE: ALL output text (kpi_labels, section_titles, card_titles, insights) MUST be in #{output_lang}. Translate if needed. Do NOT mix languages.

      Survey: "#{survey.title}"
      Total responses: #{completed_ids.size}

      ## Data:
      #{data_summary}

      ---
      ## Task 1 — #{task1_label}:
      #{kpi_texts.map.with_index { |t, i| "#{i}: #{t}" }.join("\n")}

      ## Task 2 — #{task2_label}:
      #{section_titles.map.with_index { |t, i| "#{i}: #{t}" }.join("\n")}

      ## Task 3 — #{task3_label}:
      #{card_texts.map.with_index { |t, i| "#{i}: #{t}" }.join("\n")}

      ## Task 4 — #{task4_label}:
      - type "stat": #{stat_desc}
      - type "recommendation": #{rec_desc}

      #{return_label}
      {
        "kpi_labels": ["label 0", "label 1", ...],
        "section_titles": ["title 0", "title 1", ...],
        "card_titles": ["title 0", "title 1", ...],
        "ai_insights": [
          {"type": "stat", "text": "..."},
          {"type": "recommendation", "title": "...", "detail": "..."}
        ]
      }
    MSG

    raw      = ClaudeService.sonnet.call(system_prompt: INSIGHTS_SYSTEM_PROMPT,
                                         user_prompt:   insights_prompt, max_tokens: 3000)
    json_str = raw.to_s.gsub(/\A```(?:json)?\s*|\s*```\z/, "").strip
    result   = JSON.parse(json_str)

    # Apply shortened KPI labels
    Array(result["kpi_labels"]).each_with_index do |lbl, i|
      structure["kpis"][i]["label"] = lbl.to_s.strip if structure["kpis"][i] && lbl.present?
    end

    # Apply shortened section titles
    Array(result["section_titles"]).each_with_index do |ttl, i|
      structure["sections"][i]["title"] = ttl.to_s.strip if structure["sections"][i] && ttl.present?
    end

    # Apply shortened card titles (flat index across all sections)
    if result["card_titles"].is_a?(Array)
      idx = 0
      structure["sections"].each do |sec|
        sec["cards"].each do |card|
          short = result["card_titles"][idx].to_s.strip
          card["title"] = short if short.present?
          idx += 1
        end
      end
    end

    insights = result["ai_insights"] || []
    structure["ai_insights"] = Array(insights).select { |i| i["text"].present? || i["title"].present? }

    # ── AI theme label generation for text question cards ────────────────
    structure["sections"].each do |sec|
      sec["cards"].each do |card|
        next unless card["processing"].in?(%w[normalize_tools extract_themes])
        qid = card["question_id"]&.to_i
        next unless qid
        sem = semantics_builder.semantics[qid]
        texts = sem&.dig(:texts) || []
        next if texts.size < 3

        ai_options = generate_ai_theme_labels(texts, card["title"].to_s, language)
        card["ai_options"] = ai_options if ai_options.present?
      rescue => e
        Rails.logger.warn "AI theme labels failed for Q#{qid}: #{e.message}"
      end
    end

    settings = survey.settings.to_h.merge(
      "report_structure_#{language}"         => structure,
      "report_structure_#{language}_version" => Time.current.to_i.to_s
    )
    survey.update_columns(settings: settings)
    Rails.logger.info "GenerateReportStructureJob: survey #{survey_id} [#{language}] done — #{structure['sections']&.length} sections, #{structure['ai_insights']&.length} insights"

  rescue JSON::ParserError => e
    Rails.logger.error "GenerateReportStructureJob JSON error survey #{survey_id}: #{e.message}\nRaw: #{raw.to_s.first(500)}"
    # Save structure without insights rather than full fallback
    if defined?(structure) && structure["sections"].present?
      structure["ai_insights"] = []
      survey.update_columns(settings: survey.settings.to_h.merge("report_structure_#{language}" => structure,
                                                                   "report_structure_#{language}_version" => Time.current.to_i.to_s))
    else
      save_fallback_structure(survey)
    end
  rescue => e
    Rails.logger.error "GenerateReportStructureJob error survey #{survey_id}: #{e.class} #{e.message}"
    save_fallback_structure(survey)
  end

  private

  # ── AI theme label generation from raw text responses ──────────────────────
  def generate_ai_theme_labels(texts, question_title, language = "vi")
    sample = texts.map(&:to_s).reject(&:blank?).first(30).map { |t| t.truncate(200) }
    return [] if sample.empty?

    lang_name = language == "vi" ? "Vietnamese (tiếng Việt)" : "English"
    system_prompt = "You are a survey analyst. Analyze text responses and group them into themes. Return ONLY valid JSON array. No markdown. ALL label text MUST be written in #{lang_name} — never use another language."

    user_prompt = <<~PROMPT
      Survey question: "#{question_title}"
      Total responses: #{texts.size}

      Sample responses (up to 30):
      #{sample.each_with_index.map { |t, i| "#{i+1}. #{t}" }.join("\n")}

      Task: Group these responses into 4-8 meaningful themes/categories.
      - IMPORTANT: Every "label" value MUST be in #{lang_name}. Do NOT use English if the language is Vietnamese.
      - Each theme label must be SHORT (2-5 words max), clear, descriptive
      - Count how many of the #{texts.size} total responses fit each theme (estimate based on sample)
      - Cover the most common topics; themes should not overlap heavily

      Return JSON array:
      [
        {"label": "nhãn ngắn bằng #{language == "vi" ? "tiếng Việt" : "English"}", "count": <estimated count>, "pct": <estimated %>},
        ...
      ]
      Order by count descending.
    PROMPT

    raw = ClaudeService.haiku.call(system_prompt: system_prompt, user_prompt: user_prompt, max_tokens: 600)
    clean = raw.to_s.gsub(/\A\s*```(?:json)?\s*/i, "").gsub(/\s*```\s*\z/, "").strip
    arr = JSON.parse(clean.match(/\[.*\]/m)&.to_s || "[]")
    arr.select { |o| o["label"].present? && o["count"].to_i > 0 }.first(8)
  rescue => e
    Rails.logger.warn "generate_ai_theme_labels failed: #{e.message}"
    []
  end

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
    %w[vi en].each do |lang|
      survey.update_columns(settings: survey.settings.to_h.merge("report_structure_#{lang}" => structure,
                                                                  "report_structure_#{lang}_version" => Time.current.to_i.to_s))
    end
  end
end
