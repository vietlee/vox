class ApplicationController < ActionController::Base
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :set_current_workspace
  before_action :set_locale

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :current_workspace

  private

  def current_workspace
    @current_workspace
  end

  def set_current_workspace
    return if current_user&.super_admin?
    @current_workspace = current_user&.workspace
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
        format.html { redirect_to subscription_path, alert: t("ai.feature_not_available") }
        format.json { render json: { error: "AI feature not available on your plan" }, status: :payment_required }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-result", partial: "shared/ai_upgrade_prompt") }
      end
    end
  end

  def require_credits!(amount)
    subscription = current_workspace&.active_subscription
    if subscription.nil? || (!subscription.enterprise? && subscription.credit_balance < amount)
      respond_to do |format|
        format.json { render json: { error: "Insufficient AI credits" }, status: :payment_required }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("ai-result", partial: "shared/no_credits") }
      end
    end
  end
end
