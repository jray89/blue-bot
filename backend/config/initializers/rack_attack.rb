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

  # Published by /api/status so the footer states the same limits enforced here.
  PER_VISITOR_LIMITS = { per_hour: 5, per_day: 15 }.freeze

  # The visitor's address. req.ip is no good on Railway: REMOTE_ADDR is an
  # internal 100.64.x.x hop that changes on every request, and Rack does not
  # treat that range as a proxy, so it never looks at the forwarded headers.
  # Railway's edge sets X-Real-IP to the real client and overwrites any value
  # the client sends, so it is safe to key on. Fall back to req.ip elsewhere.
  def self.client_ip(req)
    req.get_header("HTTP_X_REAL_IP").presence || req.ip
  end

  def self.ask?(req)
    req.post? && req.path == ASK_PATH
  end

  # Rack::Attack reports the first exceeded throttle in definition order, so
  # longest window first: someone over both the hourly and daily limits should
  # be told about the daily one, which is the one actually keeping them out.
  throttle("ask/ip/day", limit: PER_VISITOR_LIMITS[:per_day], period: 1.day) do |req|
    client_ip(req) if ask?(req)
  end

  throttle("ask/ip/hour", limit: PER_VISITOR_LIMITS[:per_hour], period: 1.hour) do |req|
    client_ip(req) if ask?(req)
  end

  # A burst guard so one client cannot open many concurrent SSE streams and pin
  # every Puma thread — each stream holds one for its whole life.
  throttle("ask/ip/burst", limit: 2, period: 20.seconds) do |req|
    client_ip(req) if ask?(req)
  end

  # What each throttle is called when telling the visitor which one they hit.
  LIMIT_DESCRIPTIONS = {
    "ask/ip/burst" => "You're asking too quickly: the limit is %<limit>d questions every 20 seconds.",
    "ask/ip/hour" => "You've used all %<limit>d of your questions for this hour.",
    "ask/ip/day" => "You've used all %<limit>d of your questions for today."
  }.freeze

  # Throttle windows are fixed, not sliding: they reset on multiples of the
  # period, so the wait is whatever is left of the current window.
  def self.seconds_until_reset(match_data)
    period = match_data[:period].to_i
    period - (match_data[:epoch_time].to_i % period)
  end

  def self.describe_wait(seconds)
    if seconds < 60
      "#{seconds} #{'second'.pluralize(seconds)}"
    elsif seconds < 1.hour
      minutes = (seconds / 60.0).ceil
      "#{minutes} #{'minute'.pluralize(minutes)}"
    else
      hours = (seconds / 3600.0).ceil
      "about #{hours} #{'hour'.pluralize(hours)}"
    end
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    retry_after = seconds_until_reset(match_data)
    description = format(LIMIT_DESCRIPTIONS.fetch(request.env["rack.attack.matched"]), limit: match_data[:limit])

    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [ { error: "#{description} You can ask again in #{describe_wait(retry_after)}." }.to_json ]
    ]
  end
end

Rails.application.config.middleware.use Rack::Attack
