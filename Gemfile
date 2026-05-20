source "https://rubygems.org"

gem "rails", "~> 7.2.3", ">= 7.2.3.1"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Redis — cache, sessions, ActionCable pub/sub
gem "redis", ">= 4.0.1"
gem "connection_pool", "~> 2.4"

# File storage — DigitalOcean Spaces (S3-compatible)
gem "aws-sdk-s3", "~> 1.170", require: false

# Authentication & Authorization
gem "devise"
gem "devise-two-factor"
gem "pundit"

# Background jobs
gem "sidekiq"
gem "sidekiq-cron"

# AI — Anthropic Claude API
gem "faraday"
gem "faraday-retry"

# QR Code
gem "rqrcode"

# PDF export
gem "grover"

# Excel export
gem "axlsx_rails"
gem "rubyzip"

# Charts
gem "chartkick"
gem "groupdate"

# Pagination
gem "pagy"

# File uploads
gem "image_processing", "~> 1.2"

# Multi-tenancy helpers
gem "acts_as_tenant"

# Slugs
gem "friendly_id"

# Env management
gem "dotenv-rails"

# HTTP client (for Claude API)
gem "httparty"

gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "web-console"
  gem "letter_opener"

  # Deployment
  gem "capistrano",          "~> 3.18", require: false
  gem "capistrano-rails",    "~> 1.6",  require: false
  gem "capistrano-rbenv",    "~> 2.2",  require: false
  gem "capistrano3-puma",    "~> 6.0",  require: false
  gem "capistrano-sidekiq",  "~> 3.2",  require: false
  gem "ed25519",             "~> 1.3",  require: false
  gem "bcrypt_pbkdf",        "~> 1.1",  require: false
end
