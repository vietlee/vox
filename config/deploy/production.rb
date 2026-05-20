server "188.166.189.119",
  user: "deploy",
  roles: %w[web app db],
  ssh_options: {
    forward_agent: true,
    auth_methods:  %w[publickey]
  }

set :rails_env, "production"
set :stage,     :production
