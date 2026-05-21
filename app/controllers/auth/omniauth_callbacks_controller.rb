class Auth::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: [:google_oauth2, :entra_id, :failure]

  def google_oauth2
    handle_auth("Google")
  end

  def entra_id
    handle_auth("Microsoft")
  end

  def failure
    redirect_to new_user_session_path, alert: t("omniauth.failure")
  end

  private

  def handle_auth(provider_name)
    auth  = request.env["omniauth.auth"]
    @user = User.from_omniauth(auth)

    if @user.persisted?
      # ── Existing user — NEVER change role ──────────────────────────────────
      sign_in @user, event: :authentication
      return_url = session.delete(:omniauth_return_to)

      if return_url.present?
        # Came from a vote/survey/feedback link → always go back there,
        # regardless of role (admin/supporter can participate too)
        redirect_to return_url, notice: t("devise.omniauth_callbacks.success", kind: provider_name)
      elsif @user.super_admin?
        redirect_to super_admin_root_path
      elsif @user.workspace_member?
        # Admin or supporter logging in directly → dashboard
        redirect_to dashboard_path, notice: t("devise.omniauth_callbacks.success", kind: provider_name)
      else
        # Participant logging in directly → participation history
        redirect_to my_participations_path
      end

    else
      # ── New user ────────────────────────────────────────────────────────────
      if participant_context?
        # Signing up via vote/survey/feedback link → participant role, no workspace
        # (If they later want to become admin they can sign up via registration)
        @user.role = :participant
        @user.save!
        sign_in @user
        redirect_to session.delete(:omniauth_return_to) || root_path,
                    notice: t("omniauth.welcome", name: @user.display_name)
      else
        # Signing up from login page → needs workspace setup → becomes admin
        session[:omniauth_user] = {
          provider: @user.provider,
          uid:      @user.uid,
          email:    @user.email,
          name:     @user.name
        }
        redirect_to new_sso_workspace_path
      end
    end

  rescue => e
    Rails.logger.error "[OmniAuth] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to new_user_session_path, alert: t("omniauth.error")
  end

  # True if user came from a vote/survey/feedback link
  def participant_context?
    return_url = session[:omniauth_return_to].to_s
    return_url.match?(%r{/(s|v|f)/})
  end
end
