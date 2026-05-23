class Rack::Attack
  # ── Login ──────────────────────────────────────────────────────────────────
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

  # ── OmniAuth ───────────────────────────────────────────────────────────────
  throttle("omniauth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/users/auth/})
  end

  # ── Vote submissions ────────────────────────────────────────────────────────
  # Max 5 vote submissions per IP per minute
  throttle("votes/submit/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/v/.+/submit}) && req.post?
  end

  # ── Survey submissions ──────────────────────────────────────────────────────
  # Max 5 survey submissions per IP per minute
  throttle("surveys/submit/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/s/.+/submit}) && req.post?
  end

  # ── Feedback submissions ────────────────────────────────────────────────────
  throttle("feedbacks/submit/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{^/f/}) && req.post?
  end

  # ── Response for throttled requests ────────────────────────────────────────
  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]
    [
      429,
      {
        "Content-Type"  => "application/json",
        "Retry-After"   => retry_after.to_s
      },
      [{ error: "Quá nhiều yêu cầu. Vui lòng thử lại sau.", retry_after: retry_after }.to_json]
    ]
  end
end
