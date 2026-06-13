module HtmlReportSetup
  extend ActiveSupport::Concern

  def call_html_report_setup
    @questions        = @survey.questions.includes(:question_options).order(:position)
    @total_responses  = @survey.responses.completed.count
    @report_structure = @survey.settings&.dig("report_structure")

    responses  = @survey.responses.completed.includes(:answers).to_a
    all_answers = responses.flat_map(&:answers)

    # Build option_id → label lookup
    opt_label = @questions.flat_map(&:question_options)
                          .each_with_object({}) { |o, h| h[o.id.to_i] = o.label }

    # Per-question generic stats
    @question_stats = {}
    @questions.each do |q|
      answers = all_answers.select { |a| a.question_id == q.id }
      @question_stats[q.id] = compute_question_stats(q, answers, opt_label, @total_responses)
    end

    # KPI values (driven by report_structure kpis config)
    @kpi_values = build_kpi_values(@report_structure&.dig("kpis") || [], @question_stats, @total_responses)

    # Date range
    @survey_date_range = begin
      dates = responses.map(&:completed_at).compact
      "#{dates.min.strftime('%d/%m/%Y')} – #{dates.max.strftime('%d/%m/%Y')}" if dates.any?
    end
  end

  private

  def compute_question_stats(q, answers, opt_label, total_responses) # rubocop:disable Metrics/MethodLength
    base = { id: q.id, title: q.title, question_type: q.question_type, count: answers.size }

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
        max_scale = q.question_options.maximum(:value)&.to_i || (q.question_type == "nps" ? 10 : 5)
        dist = (1..max_scale).map do |v|
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
      texts = answers.map(&:text_value).compact.reject(&:blank?)
      quotes = texts.select { |t| t.length >= 40 }
                    .sort_by(&:length).last(8)
                    .map { |t| t.truncate(300) }
      base.merge(texts: texts, quotes: quotes, total: texts.size)

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

  def build_kpi_values(kpi_configs, question_stats, total_responses)
    kpi_configs.map do |kpi|
      value = case kpi["source"]
              when "total_responses"
                total_responses.to_s
              when "question_avg"
                stats = question_stats[kpi["question_id"]&.to_i]
                stats&.dig(:avg)&.then { |v| v.round(1).to_s } || "—"
              when "question_top_option"
                stats = question_stats[kpi["question_id"]&.to_i]
                stats&.dig(:options)&.max_by { |o| o[:count] }&.dig(:label)&.truncate(30) || "—"
              else
                "—"
              end
      { label: kpi["label"], value: value, color: kpi["color"] || "#4361ee" }
    end
  end
end
