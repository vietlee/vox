class Admin::AiController < Admin::BaseController
  def generate_survey
    return unless require_ai_feature!(:ai_survey_builder)
    return unless require_credits!(5)

    current_workspace.active_subscription&.deduct_credits!(5)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "survey_builder",
      credits_cost: 5,
      input_data: { prompt: params[:prompt], language: current_workspace.language }
    )
    AiSurveyBuilderJob.perform_later(job.id)
    render json: { job_id: job.id, status: "queued" }
  end

  def check_question
    return unless require_ai_feature!(:ai_survey_builder)
    return unless require_credits!(1)

    current_workspace.active_subscription&.deduct_credits!(1)
    job = AiJob.create!(
      workspace: current_workspace,
      user: current_user,
      job_type: "question_checker",
      credits_cost: 1,
      input_data: { question_text: params[:question_text], language: current_workspace.language }
    )
    AiQuestionCheckerJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def analyze_survey
    return unless require_ai_feature!(:ai_analysis)
    return unless require_credits!(5)

    survey = current_workspace.surveys.find(params[:survey_id])
    current_workspace.active_subscription&.deduct_credits!(5)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "survey_analysis", resource_type: "Survey", resource_id: survey.id, credits_cost: 5)
    AiSurveyAnalysisJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def generate_report
    return unless require_ai_feature!(:ai_executive_report)
    return unless require_credits!(15)

    survey = current_workspace.surveys.find(params[:survey_id])
    current_workspace.active_subscription&.deduct_credits!(15)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "executive_report", resource_type: "Survey", resource_id: survey.id, credits_cost: 15, input_data: { language: params[:language] || "vi" })
    AiExecutiveReportJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def chat_page
    return unless require_ai_feature!(:ai_chat)
  end

  def chat
    return unless require_ai_feature!(:ai_chat)
    return unless require_credits!(2)

    current_workspace.active_subscription&.deduct_credits!(2)
    job = AiJob.create!(workspace: current_workspace, user: current_user, job_type: "ai_chat", credits_cost: 2, input_data: { message: params[:message], conversation_history: params[:history] || [] })
    AiChatJob.perform_later(job.id)
    render json: { job_id: job.id }
  end

  def job_status
    job = current_workspace.ai_jobs.find(params[:id])
    render json: {
      status: job.status,
      output: job.done? ? job.output_data : nil,
      error:  job.failed? ? job.error_message : nil
    }
  end
end
