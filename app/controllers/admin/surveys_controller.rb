require "csv"

class Admin::SurveysController < Admin::BaseController
  before_action :set_survey, only: [:show, :edit, :update, :destroy, :publish, :close, :reopen, :archive, :results, :export, :export_report, :ai_analyze, :ai_report, :share, :clone]
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
      respond_to do |format|
        format.json { render json: { error: t("surveys.limit_reached") }, status: :forbidden }
        format.html { redirect_to surveys_path, alert: t("surveys.limit_reached") }
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
    @individual_responses = @survey.responses.completed
                              .includes(:answers)
                              .order(completed_at: :desc)
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

    filename = "#{@survey.title.parameterize}-#{Date.today}.csv"
    send_data "\xEF\xBB\xBF#{csv_data}", filename: filename, type: "text/csv; charset=utf-8", disposition: "attachment"
  end

  def export_report
    report = @survey.ai_analysis_results.where(result_type: "executive_report").order(created_at: :desc).first
    unless report
      redirect_to results_survey_path(@survey, tab: "report"), alert: t("surveys.results.export_report_missing")
      return
    end

    format_type = params[:format_type].presence_in(%w[excel pdf]) || "excel"
    filename_base = I18n.transliterate(@survey.title).parameterize(separator: "_").presence || "report"

    if format_type == "pdf"
      html = render_to_string(
        template: "admin/surveys/report_pdf",
        locals: { survey: @survey, report: report },
        layout: "pdf"
      )
      pdf = Grover.new(html, format: "A4", print_background: true).to_pdf
      set_download_cookie
      send_data pdf, filename: "#{filename_base}-report-#{Date.today}.pdf", type: "application/pdf", disposition: "attachment"
    else
      # Excel via axlsx
      require "axlsx"
      package = Axlsx::Package.new
      wb = package.workbook
      styles = wb.styles
      title_style   = styles.add_style(b: true, sz: 14, fg_color: "3730A3")
      heading_style = styles.add_style(b: true, sz: 11, fg_color: "4338CA", bg_color: "EEF2FF")
      body_style    = styles.add_style(sz: 11, wrap_text: true)
      meta_style    = styles.add_style(sz: 10, fg_color: "6B7280", i: true)

      wb.add_worksheet(name: t("surveys.results.report_sheet_name")) do |sheet|
        sheet.add_row [@survey.title], style: title_style
        sheet.add_row [t("surveys.results.report_generated", time: report.created_at.strftime("%d/%m/%Y %H:%M"))], style: meta_style
        sheet.add_row []

        # Executive summary
        sheet.add_row [t("surveys.results.ai_executive_summary")], style: heading_style
        sheet.add_row [report.output["executive_summary"]], style: body_style
        sheet.add_row []

        # Sections
        (report.output["sections"] || []).each do |s|
          sheet.add_row [s["heading"]], style: heading_style
          sheet.add_row [s["content"]], style: body_style
          if s["key_finding"].present?
            sheet.add_row ["💡 #{s["key_finding"]}"], style: meta_style
          end
          sheet.add_row []
        end

        # Recommendations
        recs = report.output["recommendations"] || []
        if recs.any?
          sheet.add_row [t("surveys.results.ai_recommendations")], style: heading_style
          recs.each_with_index do |rec, i|
            text = rec.is_a?(Hash) ? rec["action"] : rec
            pri  = rec.is_a?(Hash) ? rec["priority"].to_s.upcase : ""
            sheet.add_row ["#{i + 1}. #{[pri.presence, text].compact.join(" | ")}"], style: body_style
          end
          sheet.add_row []
        end

        # Conclusion
        if report.output["conclusion"].present?
          sheet.add_row [t("surveys.results.ai_conclusion")], style: heading_style
          sheet.add_row [report.output["conclusion"]], style: body_style
        end

        sheet.column_widths 100
      end

      data = package.to_stream.read
      send_data data, filename: "#{filename_base}-report-#{Date.today}.xlsx",
                      type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                      disposition: "attachment"
    end
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
      input_data: { language: params[:language] || current_workspace.language }
    )
    AiExecutiveReportJob.perform_later(job.id)
    render json: { job_id: job.id, status: "queued" }
  end

  private

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
      :title, :description, :banner_image, :status,
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
