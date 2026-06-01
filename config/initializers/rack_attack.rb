class Rack::Attack
  # Use Redis in production (via Rails cache), dedicated MemoryStore in dev/test
  # so throttles work regardless of Rails cache_store setting
  if Rails.env.production?
    cache.store = Rails.cache
  else
    cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  # ── Safelist: internal health check ────────────────────────────────────────
  safelist("allow-health") { |req| req.path == "/up" }

  # ── Login ───────────────────────────────────────────────────────────────────
  # Max 10 login attempts per IP per 5 minutes
  throttle("login/ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Max 5 login attempts per email per 5 minutes
  throttle("login/email", limit: 5, period: 5.minutes) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # ── OmniAuth ────────────────────────────────────────────────────────────────
  throttle("omniauth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/users/auth/})
  end

  # ── Vote submissions ─────────────────────────────────────────────────────────
  # 5 per minute, 15 per hour (burst + sustained)
  throttle("votes/submit/ip/min", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/v/.+/submit}) && req.post?
  end
  throttle("votes/submit/ip/hour", limit: 15, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/v/.+/submit}) && req.post?
  end

  # ── Survey submissions ───────────────────────────────────────────────────────
  # 5 per minute, 20 per hour
  throttle("surveys/submit/ip/min", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/s/.+/submit}) && req.post?
  end
  throttle("surveys/submit/ip/hour", limit: 20, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/s/.+/submit}) && req.post?
  end

  # ── Feedback submissions ─────────────────────────────────────────────────────
  # 5 per minute, 30 per hour
  throttle("feedbacks/submit/ip/min", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/f/.+/submit}) && req.post?
  end
  throttle("feedbacks/submit/ip/hour", limit: 30, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/f/.+/submit}) && req.post?
  end

  # ── Feedback upvotes ─────────────────────────────────────────────────────────
  # 30 per minute (rapid clicking)
  throttle("feedbacks/upvote/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/f/.+/upvote}) && req.post?
  end

  # ── Feedback replies ─────────────────────────────────────────────────────────
  # 10 per minute, 50 per hour
  throttle("feedbacks/reply/ip/min", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/f/.+/reply}) && req.post?
  end
  throttle("feedbacks/reply/ip/hour", limit: 50, period: 1.hour) do |req|
    req.ip if req.path.match?(%r{^/f/.+/reply}) && req.post?
  end

  # ── Auto-blocklist: IPs hitting 429 too often ────────────────────────────────
  # If an IP gets throttled 10+ times in 10 minutes → block for 1 hour
  blocklist("auto-block/repeat-offender") do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 10, findtime: 10.minutes, bantime: 1.hour) do
      req.env["rack.attack.matched"]&.start_with?("feedbacks/", "surveys/", "votes/")
    end
  end

  # ── Response for throttled requests ─────────────────────────────────────────
  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: "Quá nhiều yêu cầu. Vui lòng thử lại sau.", retry_after: retry_after }.to_json]
    ]
  end

  self.blocklisted_responder = lambda do |_request|
    [
      403,
      { "Content-Type" => "application/json" },
      [{ error: "Truy cập bị từ chối." }.to_json]
    ]
  end
end
