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
  # Browsers get a friendly HTML page; API/JSON clients keep the JSON body.
  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i
    if Rack::Attack.wants_json?(request)
      [
        429,
        { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
        [{ error: "Quá nhiều yêu cầu. Vui lòng thử lại sau.", retry_after: retry_after }.to_json]
      ]
    else
      [
        429,
        { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => retry_after.to_s },
        [Rack::Attack.throttled_html(retry_after)]
      ]
    end
  end

  self.blocklisted_responder = lambda do |request|
    if Rack::Attack.wants_json?(request)
      [403, { "Content-Type" => "application/json" }, [{ error: "Truy cập bị từ chối." }.to_json]]
    else
      [403, { "Content-Type" => "text/html; charset=utf-8" },
       [Rack::Attack.blocked_html]]
    end
  end

  # A request wants JSON when it's an XHR/API call rather than a page navigation.
  def self.wants_json?(request)
    path   = request.path.to_s
    accept = request.get_header("HTTP_ACCEPT").to_s
    xrw    = request.get_header("HTTP_X_REQUESTED_WITH").to_s
    path.start_with?("/api/") ||
      request.get_header("CONTENT_TYPE").to_s.include?("application/json") ||
      xrw.casecmp?("XMLHttpRequest") ||
      (accept.include?("application/json") && !accept.include?("text/html"))
  end

  def self.page_html(title:, heading:, body:, retry_after: nil)
    reload = retry_after.to_i.positive? ? retry_after.to_i : nil
    <<~HTML
      <!doctype html><html lang="vi"><head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{title}</title>
      #{reload ? "<meta http-equiv=\"refresh\" content=\"#{reload}\">" : ""}
      <style>
        :root{color-scheme:light dark}
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
             padding:24px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
             background:linear-gradient(160deg,#1E3A5F,#0F1F33);color:#fff}
        .card{max-width:420px;width:100%;background:rgba(255,255,255,.06);
              border:1px solid rgba(255,255,255,.12);border-radius:22px;padding:32px 28px;text-align:center;
              backdrop-filter:blur(8px)}
        .ic{font-size:44px;line-height:1;margin-bottom:14px}
        h1{font-size:22px;line-height:1.3;margin:0 0 12px}
        p{color:rgba(255,255,255,.82);line-height:1.6;font-size:15px;margin:0 0 8px}
        .count{font-variant-numeric:tabular-nums;font-weight:700;color:#fff}
        a.btn{display:inline-block;margin-top:18px;background:#fff;color:#1E3A5F;font-weight:700;
              text-decoration:none;padding:11px 22px;border-radius:12px;font-size:14px}
      </style></head><body>
        <div class="card"><div class="ic">⏳</div>#{heading}#{body}</div>
      </body></html>
    HTML
  end

  def self.throttled_html(retry_after)
    mins = [(retry_after.to_f / 60).ceil, 1].max
    page_html(
      title:   "Quá nhiều lần thử",
      heading: "<h1>Quá nhiều lần thử</h1>",
      body:    "<p>Bạn đã thử quá nhiều lần trong thời gian ngắn.</p>" \
               "<p>Vui lòng thử lại sau <span class=\"count\">#{mins}</span> phút.</p>" \
               "<a class=\"btn\" href=\"/users/sign_in\">Quay lại đăng nhập</a>",
      retry_after: retry_after
    )
  end

  def self.blocked_html
    page_html(
      title:   "Truy cập bị từ chối",
      heading: "<h1>Truy cập bị từ chối</h1>",
      body:    "<p>Yêu cầu của bạn đã bị chặn. Nếu bạn cho rằng đây là nhầm lẫn, vui lòng liên hệ quản trị viên.</p>" \
               "<a class=\"btn\" href=\"/\">Về trang chủ</a>"
    )
  end
end
