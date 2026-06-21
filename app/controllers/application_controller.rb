class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :set_current_workspace
  before_action :set_locale

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :current_workspace, :accessible_workspaces, :current_workspace_role, :current_workspace_admin?

  private

  def current_workspace
    @current_workspace
  end

  def set_current_workspace
    return if current_user&.super_admin?

    if session[:current_workspace_id].present?
      ws = accessible_workspaces.find { |w| w.id == session[:current_workspace_id].to_i }
    end
    @current_workspace = ws || current_user&.workspace
    session[:current_workspace_id] = @current_workspace&.id
  end

  # All workspaces this user can access (all owned + active memberships in other workspaces)
  def accessible_workspaces
    @accessible_workspaces ||= begin
      owned  = current_user&.owned_workspaces&.to_a || []
      # legacy: user.workspace may be set before owner_id migration
      legacy = (current_user&.workspace && owned.none? { |w| w.id == current_user.workspace_id }) ? [current_user.workspace] : []
      others = current_user&.workspace_memberships&.active&.includes(:workspace)&.map(&:workspace)&.compact || []
      (owned + legacy + others).uniq(&:id)
    end
  end

  # Role of the current user *in the current workspace*
  def current_workspace_role
    return nil unless current_user && current_workspace
    return :admin if current_workspace.owner_id == current_user.id || current_user.workspace_id == current_workspace.id
    membership = current_user.workspace_memberships.find_by(workspace: current_workspace, status: :active)
    membership&.role&.to_sym
  end

  def current_workspace_admin?
    current_workspace_role == :admin
  end

  def set_locale
    if params[:locale].present? && I18n.available_locales.map(&:to_s).include?(params[:locale])
      session[:locale] = params[:locale]
    end
    I18n.locale = session[:locale]&.to_sym ||
                  current_workspace&.language&.to_sym ||
                  :vi
  end

  def user_not_authorized
    flash[:alert] = t("errors.not_authorized")
    redirect_back(fallback_location: root_path)
  end

  def require_ai_feature!(_feature)
    true
  end

  def require_credits!(amount)
    subscription = current_workspace&.active_subscription
    if subscription.nil? || subscription.credit_balance < amount
      respond_to do |format|
        format.json { render json: { insufficient_credits: true, error: t("ai.insufficient_credits") }, status: :payment_required }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-result", partial: "shared/no_credits") }
        format.html { redirect_to billing_subscription_path, alert: t("ai.insufficient_credits") }
        format.any  { render json: { insufficient_credits: true, error: t("ai.insufficient_credits") }, status: :payment_required }
      end
      return false
    end
    true
  end

  # Returns template_id from session if it was stored within the last 30 minutes,
  # and clears it. Returns nil if absent or expired (prevents stale redirects
  # when a user visits /templates, then comes back days later to sign up normally).
  def consume_pending_template_id
    raw = session.delete(:pending_template)
    session.delete(:pending_template_id)  # clear legacy key too
    return nil unless raw.is_a?(Hash)
    # JSON session serializer converts symbol keys to strings; support both
    stored_at = raw[:at] || raw["at"]
    id        = raw[:id] || raw["id"]
    return nil if stored_at.nil? || (Time.current.to_i - stored_at.to_i) > 1800  # 30 min TTL
    id.presence
  end
end
