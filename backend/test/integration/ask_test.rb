require "test_helper"

class AskTest < ActionDispatch::IntegrationTest
  # Makes the live response stream raise IOError on any write matching
  # +fail_on+, as it does when the client has gone away mid-answer.
  module BrokenPipe
    mattr_accessor :fail_on

    def write(string)
      raise IOError, "closed stream" if BrokenPipe.fail_on&.match?(string)

      super
    end
  end
  ActionDispatch::Response::Buffer.prepend(BrokenPipe)

  # An error whose backtrace is unavailable, to prove logging tolerates it.
  class BacktracelessError < StandardError
    def backtrace = nil
  end

  teardown { BrokenPipe.fail_on = nil }

  # Parse an SSE body into [[event, data], ...], skipping comment frames such
  # as the stream primer.
  def events
    response.body.split("\n\n").filter_map do |frame|
      event = frame[/^event: (.+)$/, 1]
      data = frame[/^data: (.+)$/, 1]
      [ event.to_sym, JSON.parse(data) ] if event && data
    end
  end

  def event(name)
    events.find { |type, _| type == name }&.last
  end

  def ask(question = "How are teapots kept?", ip: "203.0.113.10")
    post "/api/ask", params: { question: question }, as: :json, env: { "REMOTE_ADDR" => ip }
  end

  test "streams sources, tokens and a clean done event" do
    client = FakeAnthropic::Client.new(route: "9, 10", answer: [ "Warm it first ", "(p. 9)." ])

    with_anthropic(client) { ask }

    assert_response :success
    assert_equal "text/event-stream", response.media_type

    sources = event(:sources)["sources"]
    assert_equal [ 9, 10 ], sources.map { |s| s["page"] }
    assert_equal "Chapter I: Fixture Chapter — Part I: Teapots, p.9", sources.first["label"]

    tokens = events.select { |type, _| type == :token }.map { |_, data| data["text"] }
    assert_equal "Warm it first (p. 9).", tokens.join

    assert_empty event(:done)["unverified_citations"]
    assert_equal 1, SpendGuard.status[:asked_today]
  end

  test "passes the routed pages to the answering model as documents" do
    client = FakeAnthropic::Client.new(route: "94", answer: [ "ok" ])

    with_anthropic(client) { ask }

    _, params = client.calls.find { |kind, _| kind == :stream }
    document = params[:messages].first[:content].first
    assert_equal "document", document[:type]
    assert_match "SYNTHETIC FIXTURE PAGE 94", document[:source][:data]
  end

  test "flags citations of pages that were never supplied" do
    client = FakeAnthropic::Client.new(route: "9", answer: [ "True (p. 9), invented (p. 77)." ])

    with_anthropic(client) { ask }

    assert_equal [ 77 ], event(:done)["unverified_citations"]
  end

  test "out-of-scope questions get no_answer and are refunded" do
    client = FakeAnthropic::Client.new(route: "NONE")

    with_anthropic(client) { ask("Best scone recipe?") }

    assert event(:no_answer)
    assert_nil event(:sources)
    assert_equal 0, SpendGuard.status[:asked_today]
    assert(client.calls.none? { |kind, _| kind == :stream }, "answering model should not be called")
  end

  test "a routing failure reports an error in-band and refunds" do
    client = FakeAnthropic::Client.new(route: RuntimeError.new("boom"))

    with_anthropic(client) { ask }

    assert_response :success
    assert_match "Something went wrong", event(:error)["message"]
    assert_equal 0, SpendGuard.status[:asked_today]
  end

  test "an upstream rate limit is reported and refunded" do
    rate_limited = Anthropic::Errors::RateLimitError.new(
      url: URI("https://api.anthropic.com/v1/messages"), status: 429, headers: {},
      body: nil, request: nil, response: nil, message: "rate limited"
    )
    client = FakeAnthropic::Client.new(route: rate_limited)

    with_anthropic(client) { ask }

    assert_match "rate limited", event(:error)["message"]
    assert_equal 0, SpendGuard.status[:asked_today]
  end

  test "rejects an empty question without spending" do
    with_anthropic(FakeAnthropic::Client.new(route: "9")) { ask("   ") }

    assert_response :bad_request
    assert_equal "Please ask a question.", response.parsed_body["error"]
    assert_equal 0, SpendGuard.status[:asked_today]
  end

  test "rejects an over-long question" do
    with_anthropic(FakeAnthropic::Client.new(route: "9")) { ask("x" * (AskController::MAX_QUESTION_LENGTH + 1)) }

    assert_response :bad_request
    assert_match "limited to #{AskController::MAX_QUESTION_LENGTH}", response.parsed_body["error"]
  end

  test "refuses once the daily spend cap is reached" do
    with_env("DAILY_QUESTION_LIMIT" => "1") do
      SpendGuard.reset!

      with_anthropic(FakeAnthropic::Client.new(route: "9", answer: [ "ok" ])) do
        ask(ip: "203.0.113.20")
        assert_response :success

        ask(ip: "203.0.113.21")
      end
    end

    assert_response :too_many_requests
    assert_match "daily question limit", response.parsed_body["error"]
  end

  test "throttles bursts from a single IP" do
    with_anthropic(FakeAnthropic::Client.new(route: "NONE")) do
      2.times do
        ask(ip: "203.0.113.30")
        assert_response :success
      end

      ask(ip: "203.0.113.30")
    end

    assert_response :too_many_requests
    assert_predicate response.headers["Retry-After"].to_i, :positive?
    assert_match "question limit", response.parsed_body["error"]

    # A different visitor is unaffected.
    with_anthropic(FakeAnthropic::Client.new(route: "NONE")) { ask(ip: "203.0.113.31") }
    assert_response :success
  end

  test "throttles by X-Real-IP when each request arrives from a different proxy hop" do
    # On Railway, REMOTE_ADDR is an internal 100.64.x.x address that changes per
    # request; the edge sets X-Real-IP to the actual client.
    send_ask = lambda do |hop|
      post "/api/ask", params: { question: "How are teapots kept?" }, as: :json,
        env: { "REMOTE_ADDR" => "100.64.0.#{hop}", "HTTP_X_REAL_IP" => "203.0.113.40" }
    end

    with_anthropic(FakeAnthropic::Client.new(route: "NONE")) do
      send_ask.call(1)
      send_ask.call(2)
      send_ask.call(3)
    end

    assert_response :too_many_requests
  end

  test "status reports capacity and corpus size without spending" do
    get "/api/status"

    assert_response :success
    body = response.parsed_body
    assert_equal 4, body["pages"]
    assert_equal BlueBook::EDITION, body["edition"]
    assert_equal 0, body["asked_today"]
  end

  test "the diagnostic stream_test endpoint is gone" do
    get "/api/stream_test"

    assert_response :not_found
  end

  test "a client hanging up mid-answer ends the stream quietly and stays charged" do
    client = FakeAnthropic::Client.new(route: "9", answer: [ "one ", "two" ])
    BrokenPipe.fail_on = /^event: token/

    with_anthropic(client) { ask }

    assert_response :success
    assert event(:sources)
    assert_nil event(:token)
    assert_nil event(:error)
    assert_nil event(:done)
    assert_equal 1, SpendGuard.status[:asked_today]
  end

  test "a rate limit while answering is reported but not refunded" do
    rate_limited = Anthropic::Errors::RateLimitError.new(
      url: URI("https://api.anthropic.com/v1/messages"), status: 429, headers: {},
      body: nil, request: nil, response: nil, message: "rate limited"
    )
    client = FakeAnthropic::Client.new(route: "9", answer: rate_limited)

    with_anthropic(client) { ask }

    assert event(:sources)
    assert_match "rate limited", event(:error)["message"]
    assert_nil event(:done)
    assert_equal 1, SpendGuard.status[:asked_today]
  end

  test "a failure while answering is reported but not refunded" do
    client = FakeAnthropic::Client.new(route: "9", answer: RuntimeError.new("boom"))

    with_anthropic(client) { ask }

    assert event(:sources)
    assert_match "Something went wrong", event(:error)["message"]
    assert_equal 1, SpendGuard.status[:asked_today]
  end

  test "an error without a backtrace is still reported" do
    client = FakeAnthropic::Client.new(route: BacktracelessError.new("no trace"))

    with_anthropic(client) { ask }

    assert_match "Something went wrong", event(:error)["message"]
    assert_equal 0, SpendGuard.status[:asked_today]
  end

  test "health check is up" do
    get "/up"

    assert_response :success
  end
end
