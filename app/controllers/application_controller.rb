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

  # All workspaces this user can access (own + active memberships in other workspaces)
  def accessible_workspaces
    @accessible_workspaces ||= begin
      own = current_user&.workspace ? [current_user.workspace] : []
      others = current_user&.workspace_memberships&.active&.includes(:workspace)&.map(&:workspace)&.compact || []
      (own + others).uniq(&:id)
    end
  end

  # Role of the current user *in the current workspace*
  def current_workspace_role
    return nil unless current_user && current_workspace
    return :admin if current_user.workspace_id == current_workspace.id
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

  def require_ai_feature!(feature)
    subscription = current_workspace&.active_subscription
    unless subscription&.has_feature?(feature)
      respond_to do |format|
        format.html { redirect_to billing_subscription_path, alert: t("ai.feature_not_available") }
        format.json { render json: { upgrade_required: true, error: t("ai.feature_not_available") }, status: :payment_required }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-result", partial: "shared/ai_upgrade_prompt") }
      end
      return false
    end
    true
  end

  def require_credits!(amount)
    subscription = current_workspace&.active_subscription
    if subscription.nil? || (!subscription.enterprise? && subscription.credit_balance < amount)
      respond_to do |format|
        format.json { render json: { upgrade_required: true, insufficient_credits: true, error: t("ai.insufficient_credits") }, status: :payment_required }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-result", partial: "shared/no_credits") }
      end
      return false
    end
    true
  end
end
