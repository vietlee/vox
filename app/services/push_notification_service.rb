class PushNotificationService
  def self.send_to_learner(learner, title:, body:, url: nil, icon: "/icon-192.png")
    new.send_to_learner(learner, title: title, body: body, url: url, icon: icon)
  end

  def send_to_learner(learner, title:, body:, url: nil, icon: "/icon-192.png")
    subs = learner.learner_push_subscriptions.where(active: true)
    return if subs.none?

    payload = JSON.generate({ title: title, body: body, icon: icon, url: url })

    subs.each do |sub|
      send_push(sub, payload)
    end
  end

  private

  def send_push(subscription, payload)
    WebPush.payload_send(
      message: payload,
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh_key,
      auth: subscription.auth_key,
      vapid: {
        subject:     ENV["VAPID_SUBJECT"],
        public_key:  ENV["VAPID_PUBLIC_KEY"],
        private_key: ENV["VAPID_PRIVATE_KEY"]
      }
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    subscription.update_columns(active: false)
  rescue => e
    Rails.logger.error("PushNotification error: #{e.message}")
  end
end
