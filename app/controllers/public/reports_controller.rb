class Public::ReportsController < ApplicationController
  include HtmlReportSetup
  skip_before_action :authenticate_user!

  def show
    token = params[:token].to_s.strip
    @survey = Survey.find_by("settings->>'report_token_vi' = ?", token)
    if @survey
      @report_lang = "vi"
    else
      @survey = Survey.find_by("settings->>'report_token_en' = ?", token)
      @report_lang = "en" if @survey
      # fallback: legacy single-token
      @survey ||= Survey.find_by("settings->>'report_token' = ?", token)
      @report_lang ||= "vi"
    end

    return render template: "public/reports/not_found", layout: false, status: :not_found unless @survey

    call_html_report_setup

    @public_view = true
    render template: "admin/surveys/html_report", layout: false
  end
end
