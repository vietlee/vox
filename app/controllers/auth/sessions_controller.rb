class Auth::SessionsController < Devise::SessionsController
  # Preserve the learner warden session across admin sign-in/out.
  def create
    with_preserved_scope(:learner) do
      super do |user|
        session[:must_change_password] = true if user.must_change_password?
      end
    end
  end

  def destroy
    with_preserved_scope(:learner) { super }
  end

  private

  def with_preserved_scope(scope)
    warden_key    = "warden.user.#{scope}.key"
    return_to_key = "#{scope}_return_to"

    saved_warden    = session[warden_key]
    saved_return_to = session[return_to_key]

    yield

    session[warden_key] = saved_warden if saved_warden.present?
    if saved_return_to.present? && session[return_to_key].blank?
      session[return_to_key] = saved_return_to
    end
  end

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
