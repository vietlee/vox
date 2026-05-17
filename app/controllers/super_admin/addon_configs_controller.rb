class SuperAdmin::AddonConfigsController < SuperAdmin::BaseController
  before_action :set_addon_config, only: [:edit, :update, :destroy]

  def index
    @addon_configs = AddonConfig.order(:addon_type, :sort_order, :price_cents)
  end

  def new
    @addon_config = AddonConfig.new(addon_type: params[:addon_type] || "resource_pack")
  end

  def create
    @addon_config = AddonConfig.new(addon_config_params)
    if @addon_config.save
      redirect_to super_admin_addon_configs_path, notice: "Đã tạo gói add-on."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @addon_config.update(addon_config_params)
      redirect_to super_admin_addon_configs_path, notice: "Đã cập nhật gói add-on."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @addon_config.destroy!
    redirect_to super_admin_addon_configs_path, notice: "Đã xoá gói add-on."
  end

  private

  def set_addon_config
    @addon_config = AddonConfig.find(params[:id])
  end

  def addon_config_params
    params.require(:addon_config).permit(
      :name, :description, :addon_type, :price_cents,
      :surveys_bonus, :votes_bonus, :feedbacks_bonus, :ai_credits_bonus,
      :active, :sort_order
    )
  end
end
