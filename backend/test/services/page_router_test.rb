require "test_helper"

class PageRouterTest < ActiveSupport::TestCase
  def route(reply)
    client = FakeAnthropic::Client.new(route: reply)
    [ PageRouter.new(client: client).call("How are teapots kept?"), client ]
  end

  test "returns the pages the model picked, sorted" do
    result, = route("94, 9")

    assert_equal [ 9, 94 ], result.pages
    refute result.none?
  end

  test "sends the routing table in the system prompt" do
    _, client = route("9")
    _, params = client.calls.first

    assert_match "Teapots, 9, 10", params[:system_]
    assert_equal PageRouter::MODEL, params[:model]
  end

  test "NONE means out of scope" do
    result, = route("NONE")

    assert result.none?
  end

  test "drops pages outside the book, non-content pages, and pages with no text" do
    # 999 out of range, 5 is contents, 240 is the index, 11 has no file.
    result, = route("999, 5, 240, 11, 10")

    assert_equal [ 10 ], result.pages
  end

  test "pulls integers out of chatty replies" do
    result, = route("I would read pages 9 and 149.")

    assert_equal [ 9, 149 ], result.pages
  end

  test "reads only text blocks, ignoring other content such as thinking" do
    response = FakeAnthropic::Response.new(
      [ FakeAnthropic::Block.new(:thinking, "maybe 94?"), FakeAnthropic::Block.new(:text, "9") ],
      FakeAnthropic::Usage.new(1000, 10)
    )
    client = Object.new
    client.define_singleton_method(:messages) { self }
    client.define_singleton_method(:create) { |**| response }

    result = PageRouter.new(client: client).call("How are teapots kept?")

    assert_equal [ 9 ], result.pages
    assert_equal response.usage, result.usage
  end
end
