# The answer is instructed to cite only the pages it was given, inline as
# "(p. 94)". Verify rather than trust: any page cited that we did not actually
# supply is a fabrication, and the frontend should say so.
module CitationVerifier
  # Matches the inline citations the answer is asked to produce, e.g. "(p. 94)".
  PATTERN = /\(p\.\s*(\d{1,3})\)/

  module_function

  # Every distinct page number cited in the text, in order of first appearance.
  def cited_pages(answer)
    answer.to_s.scan(PATTERN).flatten.map(&:to_i).uniq
  end

  # Pages cited in the answer that were not among the supplied pages.
  def unverified(answer, supplied)
    cited_pages(answer) - Array(supplied)
  end
end
