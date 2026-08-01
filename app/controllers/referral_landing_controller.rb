class ReferralLandingController < ActionController::Base
  # Public page an invite link opens: shows the code + how to redeem it.
  def show
    code    = params[:code].to_s.strip.upcase
    learner = Learner.find_by(referral_code: code)
    @code   = code
    @inviter_name = learner&.name
    @reward = Learner::REFERRAL_REWARD
    @valid  = learner.present?
    render html: page_html.html_safe
  end

  private

  def page_html
    title = @valid ? "#{@inviter_name} mời bạn dùng VOX" : "VOX Learner"
    body  = if @valid
      <<~HTML
        <div class="card">
          <div class="badge">🎁 +#{@reward} credit cho cả hai</div>
          <h1>#{ERB::Util.html_escape(@inviter_name)} mời bạn học cùng VOX</h1>
          <p>Tải app <b>VOX Learner</b>, đăng ký và nhập mã giới thiệu bên dưới —
             bạn và người mời <b>mỗi người nhận #{@reward} credit</b>.</p>
          <div class="code-label">Mã giới thiệu của bạn</div>
          <div class="code">#{ERB::Util.html_escape(@code)}</div>
          <p class="hint">Mở app VOX → Đăng ký → dán mã này vào ô “Mã giới thiệu”.</p>
        </div>
      HTML
    else
      <<~HTML
        <div class="card">
          <h1>Mã giới thiệu không hợp lệ</h1>
          <p>Liên kết mời này không còn hợp lệ. Hãy xin người mời một liên kết mới nhé.</p>
        </div>
      HTML
    end

    <<~HTML
      <!doctype html><html lang="vi"><head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{ERB::Util.html_escape(title)}</title>
      <style>
        :root{color-scheme:light dark}
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
             padding:24px;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;
             background:linear-gradient(160deg,#1E3A5F,#0F1F33);color:#fff}
        .card{max-width:420px;width:100%;background:rgba(255,255,255,.06);
              border:1px solid rgba(255,255,255,.12);border-radius:22px;padding:28px;text-align:center;
              backdrop-filter:blur(8px)}
        .badge{display:inline-block;background:rgba(74,127,168,.35);border:1px solid rgba(255,255,255,.25);
               border-radius:999px;padding:6px 14px;font-size:13px;font-weight:700;margin-bottom:14px}
        h1{font-size:22px;line-height:1.3;margin:6px 0 12px}
        p{color:rgba(255,255,255,.82);line-height:1.6;font-size:15px}
        .hint{font-size:13px;color:rgba(255,255,255,.6)}
        .code-label{margin-top:18px;font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:rgba(255,255,255,.6)}
        .code{font-size:34px;font-weight:800;letter-spacing:.18em;margin:6px 0 4px;
              font-variant-numeric:tabular-nums}
      </style></head><body>#{body}</body></html>
    HTML
  end
end
