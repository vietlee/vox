class SuperAdmin::BaseController < ApplicationController
  before_action :require_super_admin!
  before_action :touch_last_seen!
  layout "super_admin"

  private

  def require_super_admin!
    redirect_to root_path unless current_user&.super_admin?
  end

  def touch_last_seen!
    return unless current_user
    return if current_user.last_seen_at && current_user.last_seen_at > 2.minutes.ago
    current_user.update_column(:last_seen_at, Time.current)
  end

  def pagy(scope, items: 20)
    page = (params[:page] || 1).to_i
    total = scope.count
    records = scope.offset((page - 1) * items).limit(items)
    pagy_obj = Struct.new(:page, :items, :count, :pages).new(page, items, total, (total.to_f / items).ceil)
    [pagy_obj, records]
  end
end
