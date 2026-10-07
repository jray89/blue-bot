# The answer is instructed to cite only the pages it was given, inline as
# "(p. 94)". Verify rather than trust: any page cited that we did not actually
# supply is a fabrication, and the frontend should say so.
module CitationVerifier
  PAGE = /(?:pp?\.\s*)?\d{1,3}(?:\s*[-–—]\s*\d{1,3})?/
  SEPARATOR = /\s*(?:,|;|&|\band\b)\s*/

  # Matches the inline citations the answer produces. The prompt asks for
  # "(p. 94)", but the model also writes ranges and lists — "(p. 99–100)",
  # "(pp. 9, 12)", "(p. 100, referring to Form of Process VIII)" — and every
  # page in those must be checked too, or a fabricated one slips through.
  PATTERN = /\(pp?\.\s*(#{PAGE}(?:#{SEPARATOR}#{PAGE})*)[^)]*\)/

  module_function

  # Every distinct page number cited in the text, in order of first appearance.
  # A range counts as citing each page within it.
  def cited_pages(answer)
    answer.to_s.scan(PATTERN).flatten.flat_map { |list| pages_in(list) }.uniq
  end

  # Pages cited in the answer that were not among the supplied pages.
  def unverified(answer, supplied)
    cited_pages(answer) - Array(supplied)
  end

  def pages_in(list)
    list.scan(/(\d{1,3})(?:\s*[-–—]\s*(\d{1,3}))?/).flat_map do |first, last|
      from, to = [ first.to_i, (last || first).to_i ].minmax
      (from..to).to_a
    end
  end
end
