class SuperAdmin::PlanConfigsController < SuperAdmin::BaseController
  before_action :set_plan_config, only: [:edit, :update]

  def index
    @plan_configs = PlanConfig.order(:price_vnd)
    # Ensure all defaults exist
    PlanConfig.seed_defaults!
    @plan_configs = PlanConfig.order(:price_vnd)
  end

  def edit; end

  def update
    if @plan_config.update(plan_config_params)
      PlanConfig.invalidate_cache!(@plan_config.plan_key)
      redirect_to super_admin_plan_configs_path, notice: "Đã cập nhật gói #{@plan_config.display_name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_plan_config
    @plan_config = PlanConfig.find(params[:id])
  end

  def plan_config_params
    base = params.require(:plan_config).permit(:display_name, :price_vnd, :billing_cycle, :monthly_free_credits)

    # Process limits — blank string → nil (unlimited), number → integer
    raw_limits = params.dig(:plan_config, :limits) || {}
    base[:limits] = raw_limits.to_unsafe_h.transform_values { |v| v.blank? ? nil : v.to_i }

    # Process features — checkbox values are "1"/"0" strings
    raw_features = params.dig(:plan_config, :features) || {}
    base[:features] = raw_features.to_unsafe_h.transform_values { |v| v == "1" }

    base
  end
end
