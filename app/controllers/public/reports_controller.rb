class Public::ReportsController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    token = params[:token].to_s.strip
    @survey = Survey.find_by("settings->>'report_token' = ?", token)
    return render plain: "Báo cáo không tồn tại hoặc link đã bị thu hồi.", status: :not_found unless @survey

    # Run the same data-loading logic as html_report
    admin_ctrl = Admin::SurveysController.new
    admin_ctrl.instance_variable_set(:@survey, @survey)
    admin_ctrl.send(:call_html_report_setup)
    admin_ctrl.instance_variables.each { |v| instance_variable_set(v, admin_ctrl.instance_variable_get(v)) }

    @public_view = true  # hides edit controls in template
    render template: "admin/surveys/html_report", layout: false
  end
end
