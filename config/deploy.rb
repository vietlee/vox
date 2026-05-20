lock "~> 3.18"

set :application, "vox"
set :repo_url,    "https://github.com/vietlee/vox.git"

set :deploy_to,   "/var/www/vox"
set :branch,      ENV.fetch("BRANCH", "main")

# rbenv
set :rbenv_type,       :user
set :rbenv_ruby,       File.read(".ruby-version").strip.sub(/^ruby-/, "")
set :rbenv_prefix,     "RBENV_ROOT=$HOME/.rbenv RBENV_VERSION=#{fetch(:rbenv_ruby)} $HOME/.rbenv/bin/rbenv exec"
set :rbenv_path,       "$HOME/.rbenv"

# Shared files/dirs persisted across deploys
set :linked_files, %w[
  .env
]

set :linked_dirs, %w[
  log
  tmp/pids
  tmp/cache
  tmp/sockets
  storage
  public/assets
]

# Keep last 5 releases
set :keep_releases, 5

# Assets
set :assets_roles, [:web]

# Puma
set :puma_threads,    [2, 4]
set :puma_workers,    2
set :puma_bind,       "unix://#{shared_path}/tmp/sockets/puma.sock"
set :puma_state,      "#{shared_path}/tmp/pids/puma.state"
set :puma_pid,        "#{shared_path}/tmp/pids/puma.pid"
set :puma_access_log, "#{release_path}/log/puma.access.log"
set :puma_error_log,  "#{release_path}/log/puma.error.log"
set :puma_preload_app, true
set :puma_worker_timeout, nil
set :puma_init_active_record, true

# Sidekiq
set :sidekiq_config, "#{current_path}/config/sidekiq.yml"

namespace :deploy do
  desc "Seed database (run manually: cap production deploy:seed)"
  task :seed do
    on roles(:db) do |host|
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "db:seed"
        end
      end
    end
  end

  after :publishing, :restart

  after :finishing, :restart_sidekiq do
    on roles(:app) do
      execute :sudo, "systemctl restart sidekiq-vox"
    end
  end
end
