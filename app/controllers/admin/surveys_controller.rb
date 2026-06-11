require "csv"

class Admin::SurveysController < Admin::BaseController
  before_action :set_survey, only: [:show, :edit, :update, :destroy, :publish, :close, :reopen, :archive, :results, :export, :export_report, :delete_report, :ai_analyze, :ai_report, :share, :clone]
  before_action :prevent_edit_if_closed, only: [:edit, :update]

  def index
    direction = params[:sort] == "asc" ? :asc : :desc
    @sort     = params[:sort] == "asc" ? "asc" : "desc"
    surveys   = current_workspace.surveys.order(created_at: direction)
    surveys   = surveys.where(status: params[:status]) if params[:status].present?
    @pagy, @surveys = pagy(surveys, items: 15)
  end

  def show
    redirect_to results_survey_path(@survey)
  end

  def new
    @survey = current_workspace.surveys.build
  end

  def create
    @survey = current_workspace.surveys.build(survey_params)
    @survey.user = current_user

    ai_data = params[:ai_data].present? ? (JSON.parse(params[:ai_data]) rescue {}) : nil

    if @survey.save
      audit_log("survey.create", resource: @survey)
      current_workspace.increment!(:surveys_created_count)
      build_ai_questions(@survey, ai_data) if ai_data.present?
      redirect_to edit_survey_path(@survey), notice: t("surveys.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    remove_logo = params.dig(:survey, :remove_logo) == "1"
    @survey.logo.purge if remove_logo && @survey.logo.attached?

    if @survey.update(survey_params)
      audit_log("survey.update", resource: @survey)
      respond_to do |format|
        format.html { redirect_to edit_survey_path(@survey), notice: t("surveys.updated") }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { notice: t("surveys.updated") }) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @survey.destroy
    respond_to do |format|
      format.json { render json: { ok: true } }
      format.html { redirect_to surveys_path, notice: t("surveys.deleted") }
    end
  end

  def publish
    subscription = current_workspace.active_subscription
    unless subscription&.within_survey_limit?
      msg = subscription&.free? ? t("surveys.limit_reached_free", date: subscription.next_reset_date_formatted) : t("surveys.limit_reached")
      respond_to do |format|
        format.json { render json: { error: msg }, status: :forbidden }
        format.html { redirect_to surveys_path, alert: msg }
      end
      return
    end
    @survey.update!(status: :active)
    audit_log("survey.publish", resource: @survey)
    respond_to do |format|
      format.json { render json: { ok: true, status: "active" } }
      format.html { redirect_to share_survey_path(@survey), notice: t("surveys.published") }
    end
  end

  def close
    @survey.update!(status: :closed)
    audit_log("survey.close", resource: @survey)
    respond_to do |format|
      format.json { render json: { ok: true, status: "closed" } }
      format.html { redirect_to results_survey_path(@survey), notice: t("surveys.closed") }
    end
  end

  def reopen
    @survey.update!(status: :active)
    audit_log("survey.reopen", resource: @survey)
    respond_to do |format|
      format.json { render json: { ok: true, status: "active" } }
      format.html { redirect_to results_survey_path(@survey), notice: t("surveys.reopened") }
    end
  end

  def archive
    @survey.update!(status: :archived)
    audit_log("survey.archive", resource: @survey)
    respond_to do |format|
      format.json { render json: { ok: true, status: "archived" } }
      format.html { redirect_to surveys_path, notice: t("surveys.archived") }
    end
  end

  def results
    @questions       = @survey.questions.includes(:question_options, :answers)
    @total_responses = @survey.responses.completed.count
    @ai_analysis     = @survey.latest_ai_analysis
    @new_responses_since_analysis = @ai_analysis ?
      @survey.responses.completed.where("completed_at > ?", @ai_analysis.created_at).count : 0
    @pagy_responses, @individual_responses = pagy(
      @survey.responses.completed.includes(:answers).order(completed_at: :desc),
      items: 20,
      page: params[:responses_page]
    )
  end

  def share
  end

  def clone
    copy = @survey.dup
    copy.title  = "#{@survey.title} copy"
    copy.status = :draft
    copy.slug   = nil

    Survey.transaction do
      copy.save!
      @survey.questions.includes(:question_options).each do |q|
        new_q = q.dup
        new_q.survey = copy
        new_q.save!
        q.question_options.each do |opt|
          new_opt = opt.dup
          new_opt.question = new_q
          new_opt.save!
        end
      end
    end

    current_workspace.increment!(:surveys_created_count)
    audit_log("survey.clone", resource: copy)
    respond_to do |format|
      format.json { render json: { ok: true, redirect: edit_survey_path(copy) } }
      format.html { redirect_to edit_survey_path(copy), notice: t("surveys_errors.cloned") }
    end
  end

  def export
    responses = @survey.responses.completed.includes(:answers)
    questions = @survey.questions.includes(:question_options).order(:position)

    csv_data = CSV.generate(headers: true) do |csv|
      header = ["#", t("surveys.results.col_time"), t("surveys.results.col_email")]
      header += questions.map { |q| q.title.truncate(60) }
      csv << header

      responses.each_with_index do |resp, idx|
        ans_map = resp.answers.index_by(&:question_id)
        row = [idx + 1, resp.completed_at&.strftime("%d/%m/%Y %H:%M"), resp.respondent_email.presence || resp.respondent_token&.last(8)]
        questions.each do |q|
          ans = ans_map[q.id]
          row << if ans.nil?
            ""
          elsif ans.text_value.present?
            ans.text_value
          elsif ans.numeric_value.present?
            ans.numeric_value.to_s
          elsif ans.option_ids.present?
            option_labels = q.question_options.each_with_object({}) { |o, h| h[o.id.to_s] = o.label }
            ans.option_ids.map { |id| option_labels[id.to_s] || id }.join(", ")
          elsif ans.date_value.present?
            ans.date_value.to_s
          else
            ""
          end
        end
        csv << row
      end
    end

    filename = "#{vi_parameterize(@survey.title)}-#{Date.today}.csv"
    send_data "\xEF\xBB\xBF#{csv_data}", filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  def export_report
    report = if params[:report_id].present?
               @survey.ai_analysis_results.find_by(id: params[:report_id], result_type: "executive_report")
             else
               @survey.ai_analysis_results.where(result_type: "executive_report").order(created_at: :desc).first
             end

    unless report
      redirect_to results_survey_path(@survey, tab: "report"), alert: t("surveys.results.export_report_missing")
      return
    end

    # Prefer stored format from metadata, fall back to param
    stored_format = report.output.dig("_meta", "format")
    format_type   = params[:format_type].presence_in(%w[excel pdf word]) || stored_format || "pdf"
    filename_base = vi_parameterize(@survey.title).presence || "report"

    if format_type == "pdf"
      html = render_to_string(
        template: "admin/surveys/report_pdf",
        locals: { survey: @survey, report: report },
        layout: "pdf"
      )
      pdf = Grover.new(html, format: "A4", print_background: true).to_pdf
      set_download_cookie
      send_data pdf, filename: "#{filename_base}-report-#{Date.today}.pdf", type: "application/pdf", disposition: "attachment"
    elsif format_type == "word"
      html = render_to_string(
        template: "admin/surveys/report_word",
        locals: { survey: @survey, report: report },
        layout: false
      )
      html = html.gsub(/\s*<!-- (BEGIN|END) [^\-]*-->\s*/, "")
      send_data html, filename: "#{filename_base}-report-#{Date.today}.doc",
                      type: "application/msword", disposition: "attachment"
    else
      # Excel via axlsx — multi-sheet with charts
      require "axlsx"
      rpt         = report.output
      rpt_meta    = rpt["_meta"] || {}
      rpt_recs    = rpt["recommendations"] || []
      rpt_secs    = rpt["sections"] || []
      km          = rpt["key_metrics"] || {}
      pos_val     = km["sentiment_positive"].to_s.gsub('%', '').to_f
      neg_val     = km["sentiment_negative"].to_s.gsub('%', '').to_f
      neu_val     = [100.0 - pos_val - neg_val, 0].max.round(1)

      package = Axlsx::Package.new
      package.use_shared_strings = true
      wb = package.workbook
      s  = wb.styles

      # ── Styles ────────────────────────────────────────────────────────
      title_s   = s.add_style(b: true, sz: 16, fg_color: "1E1B4B", alignment: { horizontal: :left })
      sub_s     = s.add_style(sz: 11, fg_color: "6B7280", i: true)
      head_s    = s.add_style(b: true, sz: 12, fg_color: "FFFFFF", bg_color: "3730A3",
                               alignment: { horizontal: :center, wrap_text: true })
      col_head_s= s.add_style(b: true, sz: 11, fg_color: "3730A3", bg_color: "EEF2FF",
                               border: { style: :thin, color: "C7D2FE", edges: [:bottom] })
      body_s    = s.add_style(sz: 11, wrap_text: true, alignment: { vertical: :top })
      num_s     = s.add_style(sz: 11, alignment: { horizontal: :center, vertical: :top })
      kpi_val_s = s.add_style(b: true, sz: 20, fg_color: "3730A3", alignment: { horizontal: :center })
      kpi_lbl_s = s.add_style(sz: 10, fg_color: "6B7280", alignment: { horizontal: :center })
      high_s    = s.add_style(b: true, sz: 10, fg_color: "FFFFFF", bg_color: "DC2626",
                               alignment: { horizontal: :center })
      med_s     = s.add_style(b: true, sz: 10, fg_color: "FFFFFF", bg_color: "D97706",
                               alignment: { horizontal: :center })
      low_s     = s.add_style(b: true, sz: 10, fg_color: "FFFFFF", bg_color: "16A34A",
                               alignment: { horizontal: :center })
      note_s    = s.add_style(sz: 10, fg_color: "92400E", bg_color: "FEF3C7", i: true,
                               alignment: { wrap_text: true, vertical: :top })
      find_s    = s.add_style(sz: 10, fg_color: "1E40AF", bg_color: "EFF6FF", i: true,
                               alignment: { wrap_text: true, vertical: :top })

      # ═══════════════════════════════════════════════════════════════════
      # SHEET 1: Dashboard (Tổng Quan)
      # ═══════════════════════════════════════════════════════════════════
      wb.add_worksheet(name: "Tổng Quan") do |sheet|
        sheet.add_row [rpt["title"] || @survey.title], style: title_s
        sheet.add_row [rpt["subtitle"].presence || ""], style: sub_s
        sheet.add_row [t("surveys.results.report_generated", time: report.created_at.strftime("%d/%m/%Y %H:%M"))], style: sub_s
        sheet.add_row []

        # Warning if low response count
        resp_count = report.response_count || @survey.responses.completed.count
        if resp_count < 10
          sheet.add_row ["⚠ Lưu ý: Báo cáo dựa trên #{resp_count} phản hồi — dữ liệu mang tính tham khảo, chưa đủ đại diện thống kê."], style: note_s
          sheet.merge_cells "A5:E5"
          sheet.add_row []
        end

        # KPI header
        sheet.add_row ["Tổng phản hồi", "Tích cực", "Tiêu cực", "Trung lập", "Ngày tạo"], style: [head_s]*5
        # KPI values
        kpi_row = [
          resp_count,
          pos_val > 0 ? "#{pos_val.round(1)}%" : "—",
          neg_val > 0 ? "#{neg_val.round(1)}%" : "—",
          neu_val > 0 ? "#{neu_val.round(1)}%" : "—",
          report.created_at.strftime("%d/%m/%Y")
        ]
        sheet.add_row kpi_row, style: [kpi_val_s]*5
        sheet.add_row ["phản hồi", "tích cực", "tiêu cực", "trung lập", "ngày báo cáo"], style: [kpi_lbl_s]*5

        if km["top_concern"].present?
          sheet.add_row []
          sheet.add_row ["Vấn đề trọng tâm: #{km["top_concern"]}"], style: note_s
          sheet.merge_cells "A#{sheet.rows.count}:E#{sheet.rows.count}"
        end

        sheet.add_row []

        # ── Chart data (hidden rows, used by pie chart) ──────────────────
        chart_data_start = sheet.rows.count + 1
        sheet.add_row ["Phân tích cảm xúc", "Tỉ lệ (%)"], style: col_head_s
        sheet.add_row ["Tích cực", pos_val]  if pos_val > 0
        sheet.add_row ["Tiêu cực", neg_val]  if neg_val > 0
        sheet.add_row ["Trung lập", neu_val] if neu_val > 0
        chart_data_end = sheet.rows.count

        # ── Pie chart: Sentiment ─────────────────────────────────────────
        if pos_val > 0 || neg_val > 0
          sheet.add_chart(Axlsx::Pie3DChart, title: "Phân Tích Cảm Xúc",
                          start_at: "G2", end_at: "O20") do |chart|
            chart.add_series(
              data:   sheet["B#{chart_data_start + 1}:B#{chart_data_end}"],
              labels: sheet["A#{chart_data_start + 1}:A#{chart_data_end}"],
              title:  "Cảm xúc"
            )
            chart.d_lbls.show_percent = true
            chart.d_lbls.show_cat_name = true
            chart.d_lbls.show_val = false
          end
        end

        # ── Recommendation priority breakdown (bar chart data) ───────────
        if rpt_recs.any?
          sheet.add_row []
          pri_counts = rpt_recs.group_by { |r| r.is_a?(Hash) ? r["priority"].to_s : "low" }
                               .transform_values(&:count)
          pri_data_start = sheet.rows.count + 1
          sheet.add_row ["Mức độ ưu tiên", "Số lượng đề xuất"], style: col_head_s
          sheet.add_row ["CAO (High)",   pri_counts["high"]  || 0]
          sheet.add_row ["TRUNG BÌNH",   pri_counts["medium"]|| 0]
          sheet.add_row ["THẤP (Low)",   pri_counts["low"]   || 0]
          pri_data_end = sheet.rows.count

          sheet.add_chart(Axlsx::Bar3DChart, title: "Đề Xuất Theo Mức Ưu Tiên",
                          bar_dir: :col, start_at: "G21", end_at: "O36") do |chart|
            chart.add_series(
              data:   sheet["B#{pri_data_start + 1}:B#{pri_data_end}"],
              labels: sheet["A#{pri_data_start + 1}:A#{pri_data_end}"],
              title:  "Số đề xuất"
            )
            chart.d_lbls.show_val = true
          end
        end

        sheet.column_widths 22, 14, 14, 14, 14
      end

      # ═══════════════════════════════════════════════════════════════════
      # SHEET 2: Nội Dung (Executive Summary + Sections)
      # ═══════════════════════════════════════════════════════════════════
      wb.add_worksheet(name: "Phân Tích") do |sheet|
        sheet.add_row [rpt["title"] || @survey.title], style: title_s
        sheet.add_row []

        sheet.add_row [t("surveys.results.ai_executive_summary")], style: head_s
        sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
        sheet.add_row [rpt["executive_summary"]], style: body_s
        sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
        sheet.add_row []

        rpt_secs.each_with_index do |sec, idx|
          sheet.add_row ["#{idx + 1}. #{sec["heading"]}"], style: col_head_s
          sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
          sheet.add_row [sec["content"]], style: body_s
          sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
          if sec["key_finding"].present?
            sheet.add_row ["💡 #{sec["key_finding"]}"], style: find_s
            sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
          end
          sheet.add_row []
        end

        if rpt["conclusion"].present?
          sheet.add_row [t("surveys.results.ai_conclusion")], style: head_s
          sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
          sheet.add_row [rpt["conclusion"]], style: body_s
          sheet.merge_cells "A#{sheet.rows.count}:B#{sheet.rows.count}"
        end

        sheet.column_widths 30, 90
      end

      # ═══════════════════════════════════════════════════════════════════
      # SHEET 3: Đề Xuất (Recommendations table)
      # ═══════════════════════════════════════════════════════════════════
      if rpt_recs.any?
        wb.add_worksheet(name: "Đề Xuất") do |sheet|
          sheet.add_row [t("surveys.results.ai_recommendations")], style: title_s
          sheet.merge_cells "A1:E1"
          sheet.add_row []
          sheet.add_row ["#", "Ưu tiên", "Hành động", "Lý do", "Tác động kỳ vọng"],
                         style: [col_head_s]*5

          pri_style = { "high" => high_s, "medium" => med_s, "low" => low_s }
          pri_label = { "high" => "CAO", "medium" => "TB", "low" => "THẤP" }

          rpt_recs.each_with_index do |rec, i|
            if rec.is_a?(Hash)
              pri = rec["priority"].to_s
              sheet.add_row [
                i + 1,
                pri_label[pri] || pri.upcase,
                rec["action"],
                rec["rationale"],
                rec["expected_impact"]
              ], style: [num_s, (pri_style[pri] || num_s), body_s, body_s, body_s]
            else
              sheet.add_row [i + 1, "", rec.to_s, "", ""], style: [num_s, num_s, body_s, body_s, body_s]
            end
          end

          sheet.column_widths 4, 8, 45, 45, 35
        end
      end

      data = package.to_stream.read
      send_data data, filename: "#{filename_base}-report-#{Date.today}.xlsx",
                      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                      disposition: "attachment"
    end
  end

  def delete_report
    report = @survey.ai_analysis_results.find_by(id: params[:report_id], result_type: "executive_report")
    report&.destroy
    render json: { ok: true }
  end

  def ai_analyze
    return unless require_ai_feature!(:ai_analysis)
    return unless require_credits!(5)

    language = params[:language].presence_in(%w[vi en]) || current_workspace.language || "vi"
    current_workspace.active_subscription&.deduct_credits!(5)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "survey_analysis",
      resource_type: "Survey",
      resource_id: @survey.id,
      credits_cost: 5,
      input_data: { language: language }
    )
    AiSurveyAnalysisJob.perform_later(job.id)

    respond_to do |format|
      format.json { render json: { job_id: job.id, status: "queued" } }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-panel", partial: "admin/surveys/ai_loading", locals: { job: job }) }
    end
  end

  def ai_report
    return unless require_ai_feature!(:ai_executive_report)
    return unless require_credits!(15)

    current_workspace.active_subscription&.deduct_credits!(15)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "executive_report",
      resource_type: "Survey",
      resource_id: @survey.id,
      credits_cost: 15,
      input_data: {
        language:     params[:language] || current_workspace.language,
        user_context: params[:user_context].presence,
        format:       params[:format].presence_in(%w[pdf excel word]) || "pdf"
      }
    )
    AiExecutiveReportJob.perform_later(job.id)
    render json: { job_id: job.id, status: "queued" }
  end

  private

  VIET_MAP = {
    # a
    "à"=>"a","á"=>"a","â"=>"a","ã"=>"a","ä"=>"a","å"=>"a",
    "ả"=>"a","ạ"=>"a",
    "ă"=>"a","ắ"=>"a","ặ"=>"a","ằ"=>"a","ẳ"=>"a","ẵ"=>"a",
    "ầ"=>"a","ấ"=>"a","ậ"=>"a","ẩ"=>"a","ẫ"=>"a",
    # e
    "è"=>"e","é"=>"e","ê"=>"e","ë"=>"e",
    "ẻ"=>"e","ẹ"=>"e",
    "ề"=>"e","ế"=>"e","ệ"=>"e","ể"=>"e","ễ"=>"e",
    # i
    "ì"=>"i","í"=>"i","î"=>"i","ï"=>"i","ỉ"=>"i","ĩ"=>"i","ị"=>"i",
    # o
    "ò"=>"o","ó"=>"o","ô"=>"o","õ"=>"o","ö"=>"o",
    "ỏ"=>"o","ọ"=>"o",
    "ơ"=>"o","ờ"=>"o","ớ"=>"o","ợ"=>"o","ở"=>"o","ỡ"=>"o",
    "ồ"=>"o","ố"=>"o","ộ"=>"o","ổ"=>"o","ỗ"=>"o",
    # u
    "ù"=>"u","ú"=>"u","û"=>"u","ü"=>"u",
    "ủ"=>"u","ụ"=>"u",
    "ư"=>"u","ừ"=>"u","ứ"=>"u","ự"=>"u","ử"=>"u","ữ"=>"u",
    # y
    "ỳ"=>"y","ý"=>"y","ỷ"=>"y","ỹ"=>"y","ỵ"=>"y",
    # d
    "đ"=>"d",
    # A
    "À"=>"A","Á"=>"A","Â"=>"A","Ã"=>"A",
    "Ả"=>"A","Ạ"=>"A",
    "Ă"=>"A","Ắ"=>"A","Ặ"=>"A","Ằ"=>"A","Ẳ"=>"A","Ẵ"=>"A",
    "Ầ"=>"A","Ấ"=>"A","Ậ"=>"A","Ẩ"=>"A","Ẫ"=>"A",
    # E
    "È"=>"E","É"=>"E","Ê"=>"E",
    "Ẻ"=>"E","Ẹ"=>"E",
    "Ề"=>"E","Ế"=>"E","Ệ"=>"E","Ể"=>"E","Ễ"=>"E",
    # I
    "Ì"=>"I","Í"=>"I","Î"=>"I","Ỉ"=>"I","Ĩ"=>"I","Ị"=>"I",
    # O
    "Ò"=>"O","Ó"=>"O","Ô"=>"O","Õ"=>"O",
    "Ỏ"=>"O","Ọ"=>"O",
    "Ơ"=>"O","Ờ"=>"O","Ớ"=>"O","Ợ"=>"O","Ở"=>"O","Ỡ"=>"O",
    "Ồ"=>"O","Ố"=>"O","Ộ"=>"O","Ổ"=>"O","Ỗ"=>"O",
    # U
    "Ù"=>"U","Ú"=>"U","Û"=>"U",
    "Ủ"=>"U","Ụ"=>"U",
    "Ư"=>"U","Ừ"=>"U","Ứ"=>"U","Ự"=>"U","Ử"=>"U","Ữ"=>"U",
    # Y
    "Ỳ"=>"Y","Ý"=>"Y","Ỷ"=>"Y","Ỹ"=>"Y","Ỵ"=>"Y",
    # D
    "Đ"=>"D"
  }.freeze

  def vi_parameterize(str, separator: "_")
    str.gsub(Regexp.union(VIET_MAP.keys), VIET_MAP)
       .parameterize(separator: separator)
  end

  def set_download_cookie
    token = params[:download_token].presence
    return unless token
    cookies[:fileDownloadToken] = { value: token, expires: 1.minute.from_now, path: "/" }
  end

  def set_survey
    @survey = current_workspace.surveys.find(params[:id])
  end

  def prevent_edit_if_closed
    if @survey.closed? || @survey.archived?
      respond_to do |format|
        format.json { render json: { error: t("surveys_errors.closed_no_edit") }, status: :forbidden }
        format.html { redirect_to results_survey_path(@survey), alert: t("surveys_errors.closed_no_edit") }
      end
    end
  end

  def survey_params
    params.require(:survey).permit(
      :title, :description, :banner_image, :status, :logo,
      :identity_mode, :login_providers, :starts_at, :ends_at, :max_responses,
      :max_per_user, :show_progress, :show_results, :allow_edit,
      :thank_you_message, :redirect_url, :scoring_enabled
    )
  end

  VALID_QUESTION_TYPES = Question.question_types.keys.freeze

  def build_ai_questions(survey, ai_data)
    questions = ai_data["questions"]
    return if questions.blank?

    questions.each_with_index do |q, idx|
      q_type = q["question_type"].to_s
      q_type = "short_text" unless VALID_QUESTION_TYPES.include?(q_type)

      question = survey.questions.create!(
        title:         q["title"].to_s.truncate(500),
        question_type: q_type,
        required:      q["required"] != false,
        description:   q["description"].presence,
        position:      idx,
        settings:      q["settings"].is_a?(Hash) ? q["settings"] : {}
      )

      # Create options for choice-type questions
      if question.choice_type? && q["options"].is_a?(Array)
        q["options"].each_with_index do |opt, i|
          question.question_options.create!(label: opt.to_s.truncate(200), position: i)
        end
      end

      # Set scale bounds for linear_scale from settings if provided
      if question.linear_scale? && q["settings"].is_a?(Hash)
        question.update_columns(settings: q["settings"])
      end
    end
  rescue => e
    Rails.logger.error "build_ai_questions failed: #{e.message}"
  end
end
