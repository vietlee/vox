Rails.application.config.session_store :cookie_store,
  key: "_vox_session",
  expire_after: 30.days,
  secure: Rails.env.production?,
  same_site: :lax
