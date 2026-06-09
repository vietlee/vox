class SurveyMailer < ApplicationMailer
  # Unified post-submission email.
  # Sent when the survey has show_results OR allow_edit (or both),
  # and we have a recipient email (email_required or SSO login).
  def submission_receipt(response)
    @response  = response
    @survey    = response.survey
    @workspace = @survey.workspace
    @locale    = (@workspace.language.presence || "vi").to_sym

    # Build answers summary for "show results" section
    @questions_with_answers = build_answers_summary(@response)

    # Build edit URL if allow_edit is on and token exists
    if @survey.allow_edit? && @response.edit_token.present?
      @edit_url = Rails.application.routes.url_helpers.edit_survey_response_url(
        slug:  @survey.slug,
        token: @response.edit_token,
        host:  ENV.fetch("APP_HOST", "localhost:3000")
      )
    end

    subject = I18n.t("survey_mailer.submission_receipt.subject",
                     survey_title: @survey.title,
                     locale: @locale)

    mail(to: response.respondent_email, subject: subject)
  end

  private

  def build_answers_summary(response)
    option_labels = response.survey.questions
      .flat_map(&:question_options)
      .each_with_object({}) { |o, h| h[o.id.to_s] = o.label }

    response.survey.questions.includes(:question_options).map do |question|
      answer = response.answers.find { |a| a.question_id == question.id }
      display = format_answer(question, answer, option_labels)
      { question: question, answer: answer, display: display }
    end
  end

  def format_answer(question, answer, option_labels)
    return nil if answer.nil?

    case question.question_type.to_sym
    when :short_text, :long_text
      answer.text_value.presence
    when :single_choice, :dropdown
      Array(answer.option_ids).map { |id| option_labels[id.to_s] }.compact.first
    when :multiple_choice
      Array(answer.option_ids).map { |id| option_labels[id.to_s] }.compact.join(", ")
    when :rating, :linear_scale, :nps
      answer.numeric_value&.to_i&.to_s
    when :date_time
      answer.date_value&.to_s
    when :matrix
      (answer.matrix_values || {}).map { |row, val| "#{row}: #{val}" }.join(" | ")
    when :file_upload
      answer.uploaded_file.attached? ? answer.uploaded_file.filename.to_s : nil
    end
  end
end
