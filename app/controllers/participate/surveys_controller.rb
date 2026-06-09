class Participate::SurveysController < Participate::BaseController
  before_action :set_survey
  before_action :enforce_login_required!, only: [:show, :submit]
  before_action :set_edit_response, only: [:edit_response]

  def done
    session.delete(:survey_last_response_id)
  end

  def show
    @questions = @survey.questions.includes(:question_options)
    unless @survey.accepting_responses?
      render :closed and return
    end

    # Track when user opened the form for avg completion time calculation
    session["survey_start_#{@survey.id}"] = Time.current.to_i

    @already_responded = false
    @response = @survey.responses.build
  end

  # GET /s/:slug/edit/:token — load existing response for editing via email link
  def edit_response
    @questions = @survey.questions.includes(:question_options)
    unless @survey.accepting_responses?
      render :closed and return
    end
    session["survey_start_#{@survey.id}"] = Time.current.to_i
    @editing_response = @existing_response
    @previous_answers = @existing_response.answers.index_by(&:question_id)
    @previous_email   = @existing_response.respondent_email
    render :show
  end

  def submit
    unless @survey.accepting_responses?
      redirect_to participate_survey_path(@survey.slug), alert: "Survey is closed."
      return
    end

    # Edit via token: update existing response
    if params[:edit_token].present?
      existing = @survey.responses.find_by(edit_token: params[:edit_token])
      if existing
        existing.answers.destroy_all
        save_answers(existing)
        new_email = params.dig(:response, :respondent_email).presence || existing.respondent_email
        existing.update_column(:respondent_email, new_email)
        existing.answers.reload
        send_submission_receipt(existing, new_email)
        session[:survey_last_response_id] = existing.id
        respond_to do |format|
          format.json { render json: { ok: true, redirect: survey_done_path(@survey.slug) } }
          format.html { redirect_to survey_done_path(@survey.slug) }
        end
        return
      end
    end

    respondent_email = if @survey.login_required?
      current_user&.email
    else
      params.dig(:response, :respondent_email)
    end

    @response = @survey.responses.build(
      workspace:        @survey.workspace,
      respondent_token: respondent_token,
      respondent_email: respondent_email,
      user_id:          current_user&.id,
      respondent_ip:    request.remote_ip,
      source:           params[:source] || "link"
    )

    if @response.save
      save_answers(@response)
      started_at = session.delete("survey_start_#{@survey.id}")
      completion_secs = started_at ? (Time.current.to_i - started_at.to_i) : nil
      @response.complete!(completion_secs)
      session[:survey_last_response_id] = @response.id
      send_submission_receipt(@response, respondent_email)
      respond_to do |format|
        format.json { render json: { ok: true, redirect: survey_done_path(@survey.slug) } }
        format.html { redirect_to survey_done_path(@survey.slug) }
      end
    else
      respond_to do |format|
        format.json { render json: { error: @response.errors.full_messages.first }, status: :unprocessable_entity }
        format.html do
          @questions = @survey.questions.includes(:question_options)
          render :show, status: :unprocessable_entity
        end
      end
    end
  end

  private

  def set_survey
    @survey = Survey.find_by!(slug: params[:slug])
    @workspace = @survey.workspace
  end

  def set_edit_response
    @existing_response = @survey.responses.find_by(edit_token: params[:token])
    unless @existing_response
      render_not_found and return
    end
  end

  # Send post-submission email when show_results OR allow_edit is on
  # and we have a recipient email (email_required or SSO login).
  def send_submission_receipt(response, email)
    return unless @survey.show_results? || @survey.allow_edit?
    recipient = email.presence || current_user&.email
    return if recipient.blank?
    # Reload answers so mailer has them available
    response.answers.load
    SurveyMailer.submission_receipt(response).deliver_later
  end

  def enforce_login_required!
    return unless @survey.login_required?
    # Workspace members always bypass
    return if current_user&.workspace_member?
    # Check SSO provider match
    return if sso_provider_satisfied?

    session[:omniauth_return_to] = request.url
    session["user_return_to"]    = request.url
    render :login_required, status: :ok
  end

  def sso_provider_satisfied?
    return false unless current_user.present?
    return false if current_user.provider.blank?

    case @survey.effective_login_providers
    when "google"    then current_user.provider == "google_oauth2"
    when "microsoft" then current_user.provider == "entra_id"
    when "both"      then current_user.provider.in?(%w[google_oauth2 entra_id])
    else false
    end
  end

  def save_answers(response)
    @survey.questions.each do |question|
      answer_data = params.dig(:answers, question.id.to_s) || {}
      answer = response.answers.build(question: question)

      case question.question_type.to_sym
      when :short_text, :long_text
        answer.text_value = answer_data[:text]
      when :single_choice, :dropdown
        answer.option_ids = [answer_data[:option_id]].compact
      when :multiple_choice
        answer.option_ids = Array(answer_data[:option_ids])
      when :rating, :linear_scale, :nps
        answer.numeric_value = answer_data[:value].to_f
      when :matrix
        answer.matrix_values = answer_data[:matrix] || {}
      when :date_time
        answer.date_value = answer_data[:date]
      when :file_upload
        file = params.dig(:answers, question.id.to_s, :file)
        if file.present?
          begin
            answer.uploaded_file.attach(file)
          rescue => e
            Rails.logger.error("[file_upload] attach failed for question #{question.id}: #{e.class} — #{e.message}")
          end
        end
      end
      answer.save!
    end
  end
end
