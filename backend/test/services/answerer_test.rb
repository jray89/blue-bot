require "test_helper"

class AnswererTest < ActiveSupport::TestCase
  test "returns the accumulated answer and yields each fragment" do
    client = FakeAnthropic::Client.new(route: "unused", answer: [ "Warm ", "the pot ", "(p. 9)." ])
    seen = []

    answer = Answerer.new(client: client).call("How?", [ 9 ]) { |fragment| seen << fragment }

    assert_equal "Warm the pot (p. 9).", answer
    assert_equal [ "Warm ", "the pot ", "(p. 9)." ], seen
  end

  test "works without a block" do
    client = FakeAnthropic::Client.new(route: "unused", answer: [ "a", "b" ])

    assert_equal "ab", Answerer.new(client: client).call("How?", [ 9 ])
  end

  test "sends each page as a titled document followed by the question" do
    client = FakeAnthropic::Client.new(route: "unused", answer: [])

    Answerer.new(client: client).call("How are teapots kept?", [ 9, 94 ])

    kind, params = client.calls.first
    assert_equal :stream, kind
    assert_equal Answerer::MODEL, params[:model]
    assert_equal Answerer::MAX_TOKENS, params[:max_tokens]
    assert_equal({ type: "disabled" }, params[:thinking])
    assert_match BlueBook::EDITION, params[:system_]

    content = params[:messages].first[:content]
    assert_equal 3, content.size
    assert_equal [ BlueBook.label(9), BlueBook.label(94) ], content.first(2).map { |doc| doc[:title] }
    assert_match "SYNTHETIC FIXTURE PAGE 94", content[1][:source][:data]
    assert_equal({ type: "text", text: "How are teapots kept?" }, content.last)
  end

  test "returns an empty string when the model streams nothing" do
    client = FakeAnthropic::Client.new(route: "unused", answer: [])

    assert_equal "", Answerer.new(client: client).call("How?", [ 9 ])
  end
end
