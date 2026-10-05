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
