Rails.application.config.after_initialize do
  begin
    PlanConfig.seed_defaults! if ActiveRecord::Base.connection.table_exists?(:plan_configs)
  rescue => e
    Rails.logger.warn("[PlanConfig] Could not seed plan configs: #{e.message}")
  end
end
