class Public::ReportsController < ApplicationController
  include HtmlReportSetup
  skip_before_action :authenticate_user!

  def show
    token = params[:token].to_s.strip
    @survey = Survey.find_by("settings->>'report_token' = ?", token)
    return render plain: "Báo cáo không tồn tại hoặc link đã bị thu hồi.", status: :not_found unless @survey

    call_html_report_setup

    @public_view = true  # hides edit controls in template
    render template: "admin/surveys/html_report", layout: false
  end
end
