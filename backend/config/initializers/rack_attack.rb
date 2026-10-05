# Per-IP throttling for a public endpoint where every request spends money.
#
# This bounds how fast any one visitor can drain the budget. It does NOT bound
# total spend, because it cannot bound the number of distinct IPs — SpendGuard
# does that, and the Anthropic Console spend limit is the real backstop.
class Rack::Attack
  # Rack::Attack keeps its counters in a cache store, and this app sets
  # Rails.cache to :null_store (it has nothing else worth caching). Sharing that
  # would make every throttle below silently no-op, so give Rack::Attack its own
  # real store. This works because Puma runs in single mode — see config/puma.rb.
  self.cache.store = ActiveSupport::Cache::MemoryStore.new(size: 4.megabytes)

  # Only the ask endpoint costs anything. /up and /api/status stay unthrottled so
  # healthchecks and the frontend's capacity display keep working.
  ASK_PATH = "/api/ask".freeze

  throttle("ask/ip/hour", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == ASK_PATH
  end

  throttle("ask/ip/day", limit: 15, period: 1.day) do |req|
    req.ip if req.post? && req.path == ASK_PATH
  end

  # A burst guard so one client cannot open many concurrent SSE streams and pin
  # every Puma thread — each stream holds one for its whole life.
  throttle("ask/ip/burst", limit: 2, period: 20.seconds) do |req|
    req.ip if req.post? && req.path == ASK_PATH
  end

  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period].to_i

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ { error: "You've reached the question limit for now. Please try again later." }.to_json ]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack
