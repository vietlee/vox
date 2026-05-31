# Force .env values to override system environment variables that are set to empty strings.
# dotenv-rails by default skips vars already present in ENV (even if ""),
# so ANTHROPIC_API_KEY="" in the shell would prevent the real key from being loaded.
if defined?(Dotenv) && Rails.env.development?
  env_file = Rails.root.join(".env")
  Dotenv.overload(env_file.to_s) if env_file.exist?
end
