class SubscriptionMailer < ApplicationMailer
  def renewal_reminder(subscription, admin)
    @subscription = subscription
    @admin        = admin
    @workspace    = subscription.workspace
    @days_left    = (subscription.ends_at.to_date - Date.current).to_i
    @billing_url  = "#{Rails.application.routes.url_helpers.billing_subscription_url(host: ENV.fetch('APP_HOST', 'localhost:3000'))}"
    mail(to: admin.email, subject: "Gói #{@subscription.plan.upcase} của #{@workspace.name} sắp hết hạn (còn #{@days_left} ngày)")
  end

  def payment_confirmed(payment, admin)
    @payment  = payment
    @admin    = admin
    @workspace = payment.workspace
    mail(to: admin.email, subject: "Thanh toán thành công — Gói #{payment.subscription.plan.upcase} đã được kích hoạt")
  end
end
