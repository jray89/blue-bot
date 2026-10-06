require "test_helper"

class FallbackTest < ActionDispatch::IntegrationTest
  # Point Rails.public_path at a scratch directory so the test neither depends
  # on nor writes to the real backend/public, which may or may not hold a build.
  def with_public_dir
    Dir.mktmpdir do |dir|
      original = Rails.method(:public_path)
      Rails.define_singleton_method(:public_path) { Pathname.new(dir) }
      begin
        yield Pathname.new(dir)
      ensure
        Rails.define_singleton_method(:public_path, original)
      end
    end
  end

  test "serves the built index.html uncached for a client-side route" do
    with_public_dir do |dir|
      File.write(dir.join("index.html"), "<!doctype html><title>Blue Bot</title>")

      get "/some/deep/link"
    end

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_equal "<!doctype html><title>Blue Bot</title>", response.body
    assert_match "no-store", response.headers["Cache-Control"]
    assert_match "inline", response.headers["Content-Disposition"]
  end

  test "serves index.html at the root path" do
    with_public_dir do |dir|
      File.write(dir.join("index.html"), "<p>shell</p>")

      get "/"
    end

    assert_response :success
    assert_equal "<p>shell</p>", response.body
  end

  test "404s with a hint when the frontend has not been built" do
    with_public_dir { get "/some/deep/link" }

    assert_response :not_found
    assert_match "Frontend not built", response.parsed_body["error"]
  end

  test "unknown API paths are not swallowed by the fallback" do
    with_public_dir do |dir|
      File.write(dir.join("index.html"), "<p>shell</p>")

      get "/api/nope"
    end

    assert_response :not_found
    refute_equal "<p>shell</p>", response.body
  end
end
