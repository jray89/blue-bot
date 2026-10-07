require "test_helper"

class CitationVerifierTest < ActiveSupport::TestCase
  test "extracts cited pages in order of first appearance, without duplicates" do
    answer = "Warm it first (p. 9). The keeper is drawn by lot (p.10). Again (p. 9)."

    assert_equal [ 9, 10 ], CitationVerifier.cited_pages(answer)
  end

  test "ignores text that is not an inline page citation" do
    answer = "See page 94, pp. 9-10, (p. ninety) and (94)."

    assert_empty CitationVerifier.cited_pages(answer)
  end

  # The prompt asks for "(p. 94)", but the model also writes ranges and lists.
  # Skipping those would let a fabricated page through unflagged.
  test "expands page ranges, whatever the dash" do
    assert_equal [ 99, 100 ], CitationVerifier.cited_pages("Four censures (p. 99–100).")
    assert_equal [ 9, 10, 11 ], CitationVerifier.cited_pages("See (pp. 9-11).")
    assert_equal [ 9, 10 ], CitationVerifier.cited_pages("See (pp. 9—10).")
  end

  test "reads every page in a list" do
    assert_equal [ 9, 12, 14, 15, 20 ],
                 CitationVerifier.cited_pages("See (pp. 9, 12, 14–15 and 20).")
    assert_equal [ 9, 96 ], CitationVerifier.cited_pages("See (p. 9; p. 96).")
  end

  test "reads the page from a citation with a trailing note" do
    assert_equal [ 100 ],
                 CitationVerifier.cited_pages("Needs Presbytery (p. 100, referring to Form of Process VIII).")
  end

  test "reads a reversed range in page order" do
    assert_equal [ 9, 10 ], CitationVerifier.cited_pages("See (pp. 10–9).")
  end

  test "flags pages in a range that were never supplied" do
    assert_equal [ 101, 102 ], CitationVerifier.unverified("Made up (p. 99–102).", [ 99, 100 ])
  end

  test "reports nothing when every citation was supplied" do
    assert_empty CitationVerifier.unverified("A (p. 9) and B (p. 94).", [ 9, 94 ])
  end

  test "reports pages cited but never supplied" do
    assert_equal [ 120, 7 ], CitationVerifier.unverified("A (p. 9), B (p. 120), C (p. 7).", [ 9, 10 ])
  end

  test "handles an empty or nil answer" do
    assert_empty CitationVerifier.unverified("", [ 9 ])
    assert_empty CitationVerifier.unverified(nil, [ 9 ])
  end
end
