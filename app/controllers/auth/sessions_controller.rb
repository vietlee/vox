class Auth::SessionsController < Devise::SessionsController
  def create
    super do |user|
      if user.must_change_password?
        session[:must_change_password] = true
      end
    end
  end

  private

  def after_sign_in_path_for(resource)
    # Auto-use template if user recently clicked "Dùng mẫu này" before logging in
    pending_id = consume_pending_template_id
    return use_template_path(pending_id) if pending_id

    return_to = session.delete(:user_return_to)
    if return_to.present?
      return_to
    elsif resource.super_admin?
      super_admin_root_path
    elsif resource.participant?
      my_participations_path
    else
      dashboard_path
    end
  end
end
