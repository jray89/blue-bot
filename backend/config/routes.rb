Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions,
  # otherwise 500. Railway's healthcheck points here (see railway.json).
  get "up" => "rails/health#show", as: :rails_health_check

  # Ask a question. Responds as an SSE stream, not JSON.
  post "api/ask" => "ask#create"

  # Remaining daily capacity and corpus metadata. Costs nothing to call.
  get "api/status" => "ask#status"

  # Proxy-buffering diagnostic. Free to call; see StreamTestController.
  get "api/stream_test" => "stream_test#show"

  # Serve the built React app for any non-API path so client-side routing works.
  get "*path", to: "fallback#index", constraints: ->(req) { !req.path.start_with?("/api", "/up") }
  root "fallback#index"
end
