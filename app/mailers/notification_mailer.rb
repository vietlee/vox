class NotificationMailer < ApplicationMailer
  def new_feedback(feedback, admin)
    @feedback  = feedback
    @board     = feedback.feedback_board
    @workspace = feedback.workspace
    @admin     = admin
    @review_url = Rails.application.routes.url_helpers.feedback_board_feedbacks_url(
      @board,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    locale = @workspace.language&.to_sym || :vi
    subject = I18n.t("notification_mailer.new_feedback.subject", board_title: @board.title, locale: locale)
    mail(to: admin.email, subject: subject)
  end

  def new_dynamic_form_submission(submission, recipient)
    @submission  = submission
    @form        = submission.dynamic_form
    @workspace   = @form.workspace
    @recipient   = recipient
    @review_url  = Rails.application.routes.url_helpers.submissions_dynamic_form_url(
      @form,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )
    @submitted_at = I18n.l(submission.created_at, format: :short, locale: @workspace.language&.to_sym || :vi)

    subject = "[VOX] Form \"#{@form.title}\" có submission mới"
    mail(to: recipient.email, subject: subject)
  end

  def new_response(response, admin)
    @response  = response
    @survey    = response.survey
    @workspace = response.workspace
    @admin     = admin
    @results_url = Rails.application.routes.url_helpers.results_survey_url(
      @survey,
      host: ENV.fetch("APP_HOST", "localhost:3000")
    )

    locale = @workspace.language&.to_sym || :vi
    subject = I18n.t("notification_mailer.new_response.subject", survey_title: @survey.title, locale: locale)
    mail(to: admin.email, subject: subject)
  end
end
