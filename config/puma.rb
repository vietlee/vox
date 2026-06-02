threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

if ENV["RAILS_ENV"] == "production"
  app_dir  = File.expand_path("../..", __FILE__)
  shared   = File.join(app_dir, "..", "..", "shared")
  bind     "unix://#{shared}/tmp/sockets/puma.sock"
  pidfile  "#{shared}/tmp/pids/puma.pid"
  state_path "#{shared}/tmp/pids/puma.state"
  stdout_redirect "#{shared}/log/puma.log", "#{shared}/log/puma.log", true
  workers ENV.fetch("WEB_CONCURRENCY", 2)
  worker_timeout 360   # allow up to 5-min ElevenLabs TTS requests + buffer
  preload_app!
else
  port ENV.fetch("PORT", 3000)
  plugin :tmp_restart
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
