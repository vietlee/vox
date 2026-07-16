class PushNotificationService
  def self.send_to_learner(learner, title:, body:, url: nil, icon: "/icon-192.png")
    new.send_to_learner(learner, title: title, body: body, url: url, icon: icon)
  end

  def self.send_to_subscription(sub, title:, body:, url: nil, icon: "/icon-192.png")
    payload = JSON.generate({ title: title, body: body, icon: icon, url: url })
    new.send_push(sub, payload)
  end

  def send_to_learner(learner, title:, body:, url: nil, icon: "/icon-192.png")
    subs = learner.learner_push_subscriptions.where(active: true)
    return if subs.none?

    payload = JSON.generate({ title: title, body: body, icon: icon, url: url })

    subs.each do |sub|
      send_push(sub, payload)
    end
  end

  def send_push(subscription, payload)
    response = WebPush.payload_send(
      message:  payload,
      endpoint: subscription.endpoint,
      p256dh:   subscription.p256dh_key,
      auth:     subscription.auth_key,
      vapid: {
        subject:     ENV["VAPID_SUBJECT"],
        public_key:  ENV["VAPID_PUBLIC_KEY"],
        private_key: ENV["VAPID_PRIVATE_KEY"]
      }
    )
    code = response.respond_to?(:code) ? response.code.to_i : 201
    Rails.logger.info("[PushNotification] sub=#{subscription.id} status=#{code}")
    # Non-2xx outside of the gem's own error handling — deactivate
    subscription.update_columns(active: false) if code >= 400
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription => e
    Rails.logger.warn("[PushNotification] sub=#{subscription.id} expired/invalid: #{e.class}")
    subscription.update_columns(active: false)
  rescue => e
    Rails.logger.error("[PushNotification] sub=#{subscription.id} error: #{e.class}: #{e.message}")
  end
end
