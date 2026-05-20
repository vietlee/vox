# Load DSL and set up stages
require "capistrano/setup"
require "capistrano/deploy"
require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git

require "capistrano/rails"
require "capistrano/rbenv"
require "capistrano/puma"
require "capistrano/sidekiq"

install_plugin Capistrano::Puma
install_plugin Capistrano::Puma::Systemd

# Load custom tasks
Dir.glob("lib/capistrano/tasks/*.rake").each { |r| import r }
