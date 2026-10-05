# Hard ceiling on how many questions the app will answer per day.
#
# The endpoint is public and every question costs roughly $0.04 (a Haiku routing
# call plus a Sonnet answer over ~8 pages). Per-IP throttling alone does not
# bound spend, because it does not bound the number of IPs. This does.
#
# It is deliberately in-process and mutex-guarded rather than cache-backed:
# Puma runs in single mode here (no workers), so one counter really is global,
# and there is no store to misconfigure.
#
# Two limits it does NOT provide, which matter:
#   * The counter resets on deploy or restart, so a restart loop could exceed
#     the daily figure.
#   * It reasons about request counts, not actual billed tokens.
# The authoritative backstop is the spend limit configured in the Anthropic
# Console. Set one. This guard is the polite first line, not the guarantee.
class SpendGuard
  # Measured over the `bin/rails ask:batch` sample: mean $0.0336 per answered
  # question (routing $0.0104 + answering $0.016-$0.031, depending on how many
  # pages the question needs). Out-of-scope questions cost the routing call only.
  #
  # $20/month at that mean is ~19/day; 16 leaves headroom for longer answers.
  DEFAULT_DAILY_LIMIT = 16
  ESTIMATED_COST_PER_QUESTION = 0.034

  class LimitExceeded < StandardError; end

  @mutex = Mutex.new
  @day = nil
  @count = 0

  class << self
    def daily_limit
      @daily_limit ||= ENV.fetch("DAILY_QUESTION_LIMIT", DEFAULT_DAILY_LIMIT).to_i
    end

    # Reserve one question. Raises LimitExceeded rather than returning false so
    # a caller cannot proceed by forgetting to check the result.
    def consume!
      @mutex.synchronize do
        roll_over!
        raise LimitExceeded, "daily limit of #{daily_limit} questions reached" if @count >= daily_limit

        @count += 1
      end
    end

    # Hand a reservation back when the request failed before spending anything.
    def refund!
      @mutex.synchronize do
        roll_over!
        @count -= 1 if @count.positive?
      end
    end

    def status
      @mutex.synchronize do
        roll_over!
        {
          asked_today: @count,
          daily_limit: daily_limit,
          remaining: [ daily_limit - @count, 0 ].max,
          estimated_spend_today: (@count * ESTIMATED_COST_PER_QUESTION).round(3)
        }
      end
    end

    # Back to a fresh day with the limit re-read from the environment. Only the
    # test suite needs this.
    def reset!
      @mutex.synchronize do
        @day = nil
        @count = 0
        @daily_limit = nil
      end
    end

    private

    # Callers already hold the mutex.
    def roll_over!
      today = Time.now.utc.to_date
      return if @day == today

      @day = today
      @count = 0
    end
  end
end
