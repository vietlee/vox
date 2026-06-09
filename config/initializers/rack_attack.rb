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
