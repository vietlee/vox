class Admin::SurveysController < Admin::BaseController
  before_action :set_survey, only: [:show, :edit, :update, :destroy, :publish, :close, :archive, :results, :export, :ai_analyze, :ai_report, :share]

  def index
    surveys = current_workspace.surveys.order(created_at: :desc)
    surveys = surveys.where(status: params[:status]) if params[:status].present?
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

    if @survey.save
      AuditLog.record(user: current_user, action: "survey.create", resource: @survey)
      redirect_to edit_survey_path(@survey), notice: t("surveys.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @survey.update(survey_params)
      AuditLog.record(user: current_user, action: "survey.update", resource: @survey)
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
    redirect_to surveys_path, notice: t("surveys.deleted")
  end

  def publish
    subscription = current_workspace.active_subscription
    unless subscription&.within_survey_limit?
      redirect_to surveys_path, alert: t("surveys.limit_reached")
      return
    end
    @survey.update!(status: :active)
    AuditLog.record(user: current_user, action: "survey.publish", resource: @survey)
    redirect_to share_survey_path(@survey), notice: t("surveys.published")
  end

  def close
    @survey.update!(status: :closed)
    redirect_to results_survey_path(@survey), notice: t("surveys.closed")
  end

  def archive
    @survey.update!(status: :archived)
    redirect_to surveys_path, notice: t("surveys.archived")
  end

  def results
    @questions      = @survey.questions.includes(:question_options, :answers)
    @total_responses = @survey.responses.completed.count
    @ai_analysis    = @survey.latest_ai_analysis
  end

  def share
  end

  def export
    format = params[:format_type] || "csv"
    # Export logic handled by background job for large datasets
    ExportSurveyJob.perform_later(@survey.id, format, current_user.id)
    redirect_to results_survey_path(@survey), notice: t("surveys.export_queued")
  end

  def ai_analyze
    require_ai_feature!(:ai_analysis)
    require_credits!(5)

    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "survey_analysis",
      resource_type: "Survey",
      resource_id: @survey.id,
      credits_cost: 5
    )
    AiSurveyAnalysisJob.perform_later(job.id)

    respond_to do |format|
      format.json { render json: { job_id: job.id, status: "queued" } }
      format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-panel", partial: "admin/surveys/ai_loading", locals: { job: job }) }
    end
  end

  def ai_report
    require_ai_feature!(:ai_executive_report)
    require_credits!(15)

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

  def set_survey
    @survey = current_workspace.surveys.find(params[:id])
  end

  def survey_params
    params.require(:survey).permit(
      :title, :description, :banner_image, :status,
      :identity_mode, :starts_at, :ends_at, :max_responses,
      :max_per_user, :show_progress, :show_results, :allow_edit,
      :thank_you_message, :redirect_url, :scoring_enabled
    )
  end
end
