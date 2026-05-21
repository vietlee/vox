class Participate::SurveysController < Participate::BaseController
  before_action :set_survey
  before_action :enforce_login_required!, only: [:show, :submit]

  def show
    @questions = @survey.questions.includes(:question_options)
    unless @survey.accepting_responses?
      render :closed and return
    end

    if @survey.allow_edit? && (prev = find_previous_response)
      @previous_answers = prev.answers.index_by(&:question_id)
      @previous_email   = prev.respondent_email
      @already_responded = false
    else
      @already_responded = already_responded?
    end
    @response = @survey.responses.build
  end

  def submit
    unless @survey.accepting_responses?
      redirect_to participate_survey_path(@survey.slug), alert: "Survey is closed."
      return
    end

    # Allow edit: update existing response instead of creating new
    if @survey.allow_edit? && (existing = find_previous_response)
      new_email = if @survey.login_required?
        current_user&.email
      elsif @survey.email_required?
        params.dig(:response, :respondent_email).presence
      end
      existing.update_column(:respondent_email, new_email) if new_email
      existing.answers.destroy_all
      save_answers(existing)
      @response = existing
      @questions = @survey.questions.includes(:question_options, :answers)
      @stats = build_results_stats if @survey.show_results?
      render :thank_you
      return
    end

    if already_responded?
      redirect_to participate_survey_path(@survey.slug) and return
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
      source:           params[:source] || "link"
    )

    if @response.save
      save_answers(@response)
      @response.complete!
      @questions = @survey.questions.includes(:question_options, :answers)
      @stats = build_results_stats if @survey.show_results?
      render :thank_you
    else
      if @response.errors.where(:base, :already_responded).any?
        redirect_to participate_survey_path(@survey.slug)
      else
        @questions = @survey.questions.includes(:question_options)
        render :show, status: :unprocessable_entity
      end
    end
  end

  private

  def set_survey
    @survey = Survey.find_by!(slug: params[:slug])
    @workspace = @survey.workspace
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

  def find_previous_response
    if current_user.present?
      @survey.responses.completed.find_by(user_id: current_user.id) ||
        @survey.responses.completed.find_by(respondent_token: respondent_token)
    else
      @survey.responses.completed.find_by(respondent_token: respondent_token)
    end
  end

  def already_responded?
    return false unless @survey.max_per_user.to_i > 0
    completed = @survey.responses.completed
    # Check by user_id first (strongest identity)
    return true if current_user.present? && completed.exists?(user_id: current_user.id)
    return true if completed.exists?(respondent_token: respondent_token)
    if @survey.email_required? || @survey.login_required?
      email = current_user&.email || params.dig(:response, :respondent_email).presence
      return true if email && completed.exists?(respondent_email: email)
    end
    false
  end

  def build_results_stats
    @survey.questions.each_with_object({}) do |question, stats|
      answers = question.answers.joins(:response).where(responses: { status: :completed })
      if question.choice_type?
        counts = Hash.new(0)
        answers.each { |a| Array(a.option_ids).each { |id| counts[id.to_s] += 1 } }
        stats[question.id] = { type: :choice, counts: counts, total: answers.count }
      elsif question.numeric_type?
        vals = answers.where.not(numeric_value: nil).pluck(:numeric_value)
        stats[question.id] = { type: :numeric, avg: vals.empty? ? nil : (vals.sum / vals.size.to_f).round(1), count: vals.size }
      elsif question.text_type?
        recent = answers.where.not(text_value: [nil, ""]).order(created_at: :desc).limit(3).pluck(:text_value)
        stats[question.id] = { type: :text, recent: recent, count: answers.count } if recent.any?
      end
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
        answer.uploaded_file.attach(file) if file.present?
      end
      answer.save!
    end
  end
end
