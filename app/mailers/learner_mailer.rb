class LearnerMailer < ApplicationMailer
  def invite(learner, assigned_by)
    @learner     = learner
    @assigned_by = assigned_by
    @invite_url  = Rails.application.routes.url_helpers.learner_invitation_url(
      token: learner.invite_token,
      host: Rails.application.config.action_mailer.default_url_options[:host]
    )
    mail(to: learner.email, subject: "#{assigned_by.name} đã mời bạn tham gia VOX Learn")
  end

  def assignment_notification(learner, type_label, resource_title, access_url)
    @learner        = learner
    @resource_title = resource_title
    @access_url     = access_url
    @type_label     = type_label
    mail(to: learner.email, subject: "Bạn có #{type_label} mới: #{resource_title}")
  end

  # Daily nudge: protect streak + list things to do today.
  def daily_reminder(learner)
    @learner       = learner
    @streak        = learner.current_streak
    @tasks         = LearnerDailyReminderJob.pending_tasks_for(learner) # [{label:, meta:, overdue:}]
    @dashboard_url = Rails.application.routes.url_helpers.learner_root_url(
      host: Rails.application.config.action_mailer.default_url_options[:host]
    )

    subject =
      if @streak >= 1
        "🔥 Giữ chuỗi #{@streak} ngày học của bạn nhé!"
      else
        "📚 Hôm nay học gì trên VOX?"
      end

    mail(to: learner.email, subject: subject)
  end
end
