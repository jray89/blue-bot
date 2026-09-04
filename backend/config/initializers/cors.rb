# In production the frontend is built into Rails' public/ and served from the
# same origin, so CORS is not involved. This exists for local development, where
# Vite serves on another port, and for any explicitly allowed deployed origin.
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*Rails.application.config.x.allowed_origins)

    resource "/api/*",
      headers: :any,
      methods: [ :get, :post, :options ],
      # SSE responses are streamed; the browser needs to read them incrementally.
      credentials: false
  end
end
