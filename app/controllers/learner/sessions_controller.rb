class Learner::SessionsController < Devise::SessionsController
  layout "learner"
  skip_before_action :authenticate_user!
  skip_before_action :set_current_workspace

  # Preserve the admin (user) warden session across learner sign-in/out.
  # Warden's logout() calls reset_session! when no scope is given, and some
  # Devise/Rails internals may clear the full session. Saving & restoring the
  # :user warden key keeps the admin logged in regardless.
  def create
    with_preserved_scope(:user) { super }
  end

  def destroy
    with_preserved_scope(:user) { super }
  end

  protected

  def after_sign_in_path_for(resource)
    stored_location_for(:learner) || learner_root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    new_learner_session_path
  end

  private

  def with_preserved_scope(scope)
    warden_key    = "warden.user.#{scope}.key"
    return_to_key = "#{resource_name}_return_to"

    saved_warden    = session[warden_key]
    saved_return_to = session[return_to_key]

    yield

    # Restore the other scope's auth token unconditionally
    session[warden_key] = saved_warden if saved_warden.present?
    # Restore the stored return URL only if reset_session wiped it
    if saved_return_to.present? && session[return_to_key].blank?
      session[return_to_key] = saved_return_to
    end
  end
end
