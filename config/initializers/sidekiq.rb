Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" } }

  config.on(:startup) do
    schedule_file = Rails.root.join("config/sidekiq.yml")
    if File.exist?(schedule_file)
      schedule = YAML.load_file(schedule_file)
      cron = schedule[:cron] || schedule["cron"] || {}
      if cron.any?
        Sidekiq::Cron::Job.load_from_hash(cron)
        Rails.logger.info "[Sidekiq::Cron] Loaded #{cron.size} cron job(s): #{cron.keys.join(', ')}"
      end
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" } }
end
