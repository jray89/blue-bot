require "test_helper"

class BlueBookTest < ActiveSupport::TestCase
  test "loads the corpus from BLUE_BOOK_DATA_DIR" do
    assert_equal Pathname.new(ENV["BLUE_BOOK_DATA_DIR"]).cleanpath, BlueBook.root
    assert_equal 4, BlueBook.page_count
  end

  test "returns the text of a page" do
    assert_match "SYNTHETIC FIXTURE PAGE 94", BlueBook.page(94)
  end

  test "returns nil for a page in range that has no file" do
    assert_nil BlueBook.page(11)
  end

  test "returns nil for pages outside the book" do
    assert_nil BlueBook.page(0)
    assert_nil BlueBook.page(255)
    assert_nil BlueBook.page(-3)
  end

  test "labels a page with its chapter and section" do
    assert_equal "Chapter V: Another Fixture Chapter — Part III: Lighthouses, p.94", BlueBook.label(94)
    assert_equal "Chapter V: Another Fixture Chapter", BlueBook.chapter(94)
  end

  test "falls back to a bare page label when the manifest has no entry" do
    assert_equal "p.12", BlueBook.label(12)
    assert_nil BlueBook.chapter(12)
  end

  test "exposes the routing table" do
    assert_match "Teapots, 9, 10", BlueBook.routing_table
  end

  test "preload! warms everything and returns the class" do
    assert_equal BlueBook, BlueBook.preload!
  end

  test "raises MissingCorpus when BLUE_BOOK_DATA_DIR does not exist" do
    with_env("BLUE_BOOK_DATA_DIR" => "/nonexistent/blue-book") do
      BlueBook.reset!
      error = assert_raises(BlueBook::MissingCorpus) { BlueBook.preload! }
      assert_match "/nonexistent/blue-book", error.message
    end
  end

  test "raises MissingCorpus when the directory has no manifest" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "routing_table.md"), "# empty")

      with_env("BLUE_BOOK_DATA_DIR" => dir) do
        BlueBook.reset!
        error = assert_raises(BlueBook::MissingCorpus) { BlueBook.manifest }
        assert_match "manifest.json", error.message
      end
    end
  end

  # Swap File.directory? for the block so the default-location search can be
  # exercised regardless of whether a developer has a corpus cloned locally.
  def with_directories(existing)
    original = File.method(:directory?)
    File.define_singleton_method(:directory?) { |path| existing.include?(path.to_s) }
    yield
  ensure
    File.define_singleton_method(:directory?, original)
  end

  test "without BLUE_BOOK_DATA_DIR, falls back to a corpus cloned at the repo root" do
    repo_root_corpus = Rails.root.join("..", "data", "blue-book").to_s

    with_env("BLUE_BOOK_DATA_DIR" => "") do
      with_directories([ repo_root_corpus ]) do
        BlueBook.reset!
        assert_equal Pathname.new(repo_root_corpus).cleanpath, BlueBook.root
      end
    end
  end

  test "without BLUE_BOOK_DATA_DIR, prefers backend/data over the repo root" do
    backend_corpus = Rails.root.join("data", "blue-book").to_s
    repo_root_corpus = Rails.root.join("..", "data", "blue-book").to_s

    with_env("BLUE_BOOK_DATA_DIR" => nil) do
      with_directories([ backend_corpus, repo_root_corpus ]) do
        BlueBook.reset!
        assert_equal Pathname.new(backend_corpus).cleanpath, BlueBook.root
      end
    end
  end

  test "without BLUE_BOOK_DATA_DIR and no local clone, names both places it looked" do
    with_env("BLUE_BOOK_DATA_DIR" => nil) do
      with_directories([]) do
        BlueBook.reset!
        error = assert_raises(BlueBook::MissingCorpus) { BlueBook.root }
        assert_match Rails.root.join("data", "blue-book").to_s, error.message
        assert_match Rails.root.join("..", "data", "blue-book").to_s, error.message
      end
    end
  end

  test "treats a whitespace-only page file as blank" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "pages"))
      File.write(File.join(dir, "pages", "p009.md"), "  \n\n ")
      File.write(File.join(dir, "pages", "p010.md"), "Real text\n")

      with_env("BLUE_BOOK_DATA_DIR" => dir) do
        BlueBook.reset!
        assert_nil BlueBook.page(9)
        assert_equal "Real text", BlueBook.page(10)
        assert_equal 1, BlueBook.page_count
      end
    end
  end
end
