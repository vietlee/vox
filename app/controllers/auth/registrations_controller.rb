class Auth::RegistrationsController < Devise::RegistrationsController
  # Super admin creates workspace admins — direct registration disabled
  before_action :redirect_if_registration_disabled

  private

  def redirect_if_registration_disabled
    redirect_to new_user_session_path, alert: "Account creation is invitation-only."
  end
end
