# Hard ceiling on how many questions the app will answer per day.
#
# The endpoint is public and every answered question costs an estimated ~$0.033
# (a Haiku routing call plus a Sonnet answer over ~8 pages). Per-IP throttling
# alone does not bound spend, because it does not bound the number of IPs. This
# bounds answered questions.
#
# It is deliberately in-process and mutex-guarded rather than cache-backed:
# Puma runs in single mode here (no workers), so one counter really is global,
# and there is no store to misconfigure.
#
# Two limits it does NOT provide, which matter:
#   * The counter resets on deploy or restart, so a restart loop could exceed
#     the daily figure.
#   * It reasons about request counts, not actual billed tokens.
#   * It caps answered questions, not spend. When routing returns NONE or a
#     request fails before answering, AskController refunds the reservation, but
#     the routing call (~$0.01) was still billed. Those requests are bounded only
#     by per-IP throttling and the Console limit.
# The authoritative backstop is the spend limit configured in the Anthropic
# Console. Set one. This guard is the polite first line, not the guarantee.
class SpendGuard
  # An ESTIMATE, not a measurement: ~$0.033 per answered question on Sonnet 5
  # ($2/$10 per MTok) + Haiku 4.5 ($1/$5), routing ~$0.01 of it, the rest
  # growing with how many pages the question needs. Earlier "measured" figures
  # priced the answering call from character counts. Replace this with the mean
  # from a real `bin/rails ask:batch` run, which now prices both calls from the
  # API's reported usage. 0.034 rounds the estimate up. It only feeds
  # estimated_spend_today in /status, which therefore also excludes the billed
  # routing calls of refunded (NONE/failed) requests.
  #
  # $20/month at that mean is ~20/day; 16 leaves headroom for longer answers.
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
