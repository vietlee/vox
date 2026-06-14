class Public::AiReportsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    token   = params[:token].to_s.strip
    @survey = Survey.find_by("settings->>'ai_report_token' = ?", token)
    return render template: "public/reports/not_found", layout: false, status: :not_found unless @survey

    ai_report_id = @survey.settings["ai_report_id"]
    @ai_result = if ai_report_id.present?
                   @survey.ai_analysis_results.find_by(id: ai_report_id, result_type: "executive_report")
                 end
    @ai_result ||= @survey.ai_analysis_results.where(result_type: "executive_report").order(created_at: :desc).first

    return render template: "public/reports/not_found", layout: false, status: :not_found unless @ai_result

    @public_view = true
    render template: "admin/surveys/view_ai_report", layout: false
  end
end
