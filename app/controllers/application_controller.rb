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

    if ws
      @current_workspace = ws
    else
      # Session workspace not accessible (deleted, revoked, or first load).
      # Fall back to primary workspace and reset session so the next request
      # doesn't repeatedly fail the accessible_workspaces lookup.
      @current_workspace = current_user&.workspace
      session[:current_workspace_id] = @current_workspace&.id
    end
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

  # True only for the workspace owner (not added members)
  def workspace_owner?
    return false unless current_user && current_workspace
    current_workspace.owner_id == current_user.id
  end
  helper_method :workspace_owner?

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

  # Accepts either a raw Integer or a CreditCost key (Symbol), so call sites can
  # reference the single pricing source: require_credits!(:quiz_generate).
  def require_credits!(amount)
    amount = CreditCost[amount] if amount.is_a?(Symbol)
    subscription = current_workspace&.credit_subscription
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

  # Charge the workspace's billing subscription for an action, priced from the
  # single CreditCost source. Pass a CreditCost key: charge_credits!(:quiz_generate).
  def charge_credits!(cost_key)
    current_workspace&.credit_subscription&.deduct_credits!(CreditCost[cost_key])
  end

  # Token-metered charge for conversational AI (chat/tutor). Given the usage of
  # one turn, deducts the length-based credit cost from the workspace, capped at
  # the remaining balance so the last turn never raises. Returns credits charged.
  def charge_ai_tokens!(input_tokens:, output_tokens:)
    sub = current_workspace&.credit_subscription
    return 0 unless sub
    want   = AiTokenPricing.credits_for(input_tokens: input_tokens, output_tokens: output_tokens)
    charge = [want, sub.credit_balance].min
    sub.deduct_credits!(charge) if charge.positive?
    charge
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
