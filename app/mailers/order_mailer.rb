class OrderMailer < ApplicationMailer
  # No-op stub — OrderMailer was referenced by stale Sidekiq retry jobs
  # enqueued in Aug 2025 before this class existed. All methods are silent
  # no-ops so retried jobs stop crashing workers without sending any mail.

  before_action { self.class.perform_deliveries = false }

  def confirmation(*)
    Rails.logger.info "[OrderMailer] no-op: skipping stale confirmation job"
    mail(to: "noreply@void.invalid", subject: "noop") { |f| f.text { render plain: "" } }
  end
end
