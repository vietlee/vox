class Public::ReportsController < ApplicationController
  include HtmlReportSetup
  skip_before_action :authenticate_user!

  def show
    find_survey_by_token || return
    call_html_report_setup
    @public_view = true
    @pdf_preview_url  = public_report_preview_pdf_path(params[:token], lang: @report_lang)
    @html_preview_url = public_report_preview_html_path(params[:token], lang: @report_lang)
    render template: "admin/surveys/html_report", layout: false
  end

  def preview_html
    find_survey_by_token || return
    call_html_report_setup
    @public_view = true
    @pdf_preview = true
    render template: "admin/surveys/html_report", layout: false
  end

  def preview_pdf
    find_survey_by_token || return
    call_html_report_setup
    @public_view = true
    @pdf_preview_url = public_report_preview_pdf_path(params[:token], lang: @report_lang)
    params[:pdf] = "1"

    sk = "report_layout_#{@survey.id}_#{@report_lang}"
    layout_json = @survey.settings[sk]&.to_json || "{}"

    content_sig = Digest::MD5.hexdigest("#{layout_json}#{@survey.updated_at.to_i}#{@report_lang}")
    cache_key   = "pdf_preview_public/#{@survey.id}/#{content_sig}"

    pdf = Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      html = render_to_string(template: "admin/surveys/html_report", layout: false)
      layout_script = <<~JS
        <script>
          (function(){
            try {
              var data = #{layout_json.to_s.html_safe};
              if (typeof data === 'string') data = JSON.parse(data);
              localStorage.setItem('#{sk}', typeof data === 'string' ? data : JSON.stringify(data));
            } catch(e) {}
          })();
        </script>
      JS
      html = html.sub("</head>", "#{layout_script}</head>")

      Grover.new(html,
        format:              "A4",
        landscape:           true,
        print_background:    true,
        scale:               0.86,
        margin:              { top: "8mm", bottom: "8mm", left: "8mm", right: "8mm" },
        emulate_media:       "print",
        viewport:            { width: 1200, height: 900, device_scale_factor: 2 },
        wait_until:          "load",
        wait_for_function:   "window._chartsReady === true",
        timeout:             60_000
      ).to_pdf
    end

    send_data pdf, type: "application/pdf", disposition: "inline"
  rescue => e
    Rails.logger.error "public preview_pdf error: #{e.message}"
    head :internal_server_error
  end

  private

  def find_survey_by_token
    token = params[:token].to_s.strip
    @survey = Survey.find_by("settings->>'report_token_vi' = ?", token)
    if @survey
      @report_lang = "vi"
    else
      @survey = Survey.find_by("settings->>'report_token_en' = ?", token)
      @report_lang = "en" if @survey
      @survey ||= Survey.find_by("settings->>'report_token' = ?", token)
      @report_lang ||= "vi"
    end

    unless @survey
      render template: "public/reports/not_found", layout: false, status: :not_found
      return nil
    end
    true
  end
end
