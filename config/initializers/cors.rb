Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "https://vox.czin.net",
            "http://localhost:8081", "http://localhost:8080",
            "http://127.0.0.1:8081", "http://127.0.0.1:8080",
            "http://localhost:3000"

    resource "/api/learner/v1/*",
      headers: :any,
      methods: [:get, :post, :patch, :put, :delete, :options, :head],
      credentials: true,
      expose: ["X-CSRF-Token"]
  end
end
