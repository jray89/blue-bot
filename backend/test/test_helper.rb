ENV["RAILS_ENV"] ||= "test"

# Coverage must start before the app loads. Parallel workers each write their
# own result, merged under a per-process command name.
require "simplecov"
SimpleCov.start "rails" do
  enable_coverage :branch
  add_filter %w[/bin/ /config/ /test/ /vendor/]
end

# The real corpus is copyrighted and not in this repo, so the suite runs against
# a small synthetic one. BlueBook treats an explicit BLUE_BOOK_DATA_DIR as
# authoritative, so a local clone in data/blue-book can never leak in.
ENV["BLUE_BOOK_DATA_DIR"] = File.expand_path("fixtures/files/blue-book", __dir__)

# Set before dotenv runs so a developer's real key in backend/.env is never
# picked up. Nothing in the suite may reach the network anyway — see below.
ENV["ANTHROPIC_API_KEY"] = "sk-ant-test-not-a-real-key"

require_relative "../config/environment"
require "rails/test_help"

# Every Anthropic call in the suite goes through a fake. Constructing a real
# client is an error, so a test that forgets to stub fails loudly instead of
# spending money.
module FakeAnthropic
  Block = Struct.new(:type, :text)
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens)
  Response = Struct.new(:content, :usage)
  Message = Struct.new(:usage)

  # Mirrors the SDK's MessageStream: #text yields the deltas, and
  # #accumulated_message is the final message, carrying the billed usage.
  Stream = Struct.new(:text, :usage) do
    def accumulated_message = Message.new(usage)
  end

  ANSWER_USAGE = Usage.new(5000, 200, 0, 0).freeze

  # Stands in for Anthropic::Client and its #messages resource.
  #
  #   route:  the router model's reply text (e.g. "9, 10" or "NONE"), or an
  #           exception to raise from messages.create
  #   answer: fragments the answering model streams, or an exception to raise
  #           from messages.stream
  class Client
    attr_reader :calls

    def initialize(route:, answer: [])
      @route = route
      @answer = answer
      @calls = []
    end

    def messages = self

    def create(**params)
      @calls << [ :create, params ]
      raise @route if @route.is_a?(Exception)

      Response.new([ Block.new(:text, @route) ], Usage.new(1000, 10))
    end

    def stream(**params)
      @calls << [ :stream, params ]
      raise @answer if @answer.is_a?(Exception)

      Stream.new(@answer, ANSWER_USAGE)
    end
  end

  class << self
    attr_accessor :client
  end
end

Anthropic::Client.define_singleton_method(:new) do |*|
  FakeAnthropic.client or raise "unstubbed Anthropic client in test; use with_anthropic"
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}"
    end

    parallelize_teardown { SimpleCov.result }

    setup do
      FakeAnthropic.client = nil
      BlueBook.reset!
      SpendGuard.reset!
      Rack::Attack.reset!
    end

    # Run the block with every new Anthropic::Client being +client+.
    def with_anthropic(client)
      FakeAnthropic.client = client
      yield client
    ensure
      FakeAnthropic.client = nil
    end

    def with_env(vars)
      saved = vars.keys.index_with { |key| ENV[key] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      saved.each { |key, value| ENV[key] = value }
    end
  end
end
