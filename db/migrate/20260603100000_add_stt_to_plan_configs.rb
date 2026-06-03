class AddSttToPlanConfigs < ActiveRecord::Migration[7.2]
  # Add :stt feature flag to existing plan_config DB records.
  # DEFAULTS in the model are only used when no DB row exists,
  # so we must patch the stored JSONB column directly.
  STT_BY_PLAN = {
    "free"       => false,
    "pro"        => true,
    "enterprise" => true
  }.freeze

  def up
    STT_BY_PLAN.each do |plan_key, enabled|
      execute <<~SQL
        UPDATE plan_configs
        SET features = features || '{"stt": #{enabled}}'::jsonb
        WHERE plan_key = '#{plan_key}'
      SQL
    end

    # Flush Rails.cache so changes take effect immediately
    say "Invalidating plan_config cache..."
    %w[free pro enterprise].each { |k| Rails.cache.delete("plan_config/#{k}") }
  end

  def down
    %w[free pro enterprise].each do |plan_key|
      execute <<~SQL
        UPDATE plan_configs
        SET features = features - 'stt'
        WHERE plan_key = '#{plan_key}'
      SQL
    end
    %w[free pro enterprise].each { |k| Rails.cache.delete("plan_config/#{k}") }
  end
end
