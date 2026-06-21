class SuperAdmin::AiModelConfigsController < SuperAdmin::BaseController
  def show
    @configs = AiModelConfig.all_configs
  end

  def update
    permitted = params.require(:configs).permit(AiModelConfig::FEATURES.keys)
    permitted.each do |feature_key, model_id|
      next unless AiModelConfig::FEATURES.key?(feature_key)
      next unless AiModelConfig::AVAILABLE_MODELS.any? { |m| m[:id] == model_id }
      AiModelConfig.find_or_initialize_by(feature_key: feature_key).tap do |c|
        c.model_id = model_id
        c.save!
      end
    end
    AiModelConfig.invalidate_cache!
    redirect_to super_admin_ai_model_configs_path, notice: "Đã lưu cấu hình model AI"
  end
end
