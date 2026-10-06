# First of the two model calls: decide which printed pages to read.
#
# Sending the whole book (~170k tokens, ~1.3x that on Sonnet 5's tokenizer) on
# every question would cost an estimated ~$0.48 a request on Sonnet 5 (range
# $0.36-$0.55; ~14x a routed question; estimates pending a real ask:batch run),
# and prompt caching does not rescue us because a public, low-traffic app almost
# never gets a warm cache. So a cheap model reads the book's own indices — a
# retrieval map written by people who know the subject — and picks the handful
# of pages worth loading.
#
# The response is deliberately a bare list of integers rather than a structured
# schema: it is trivially validatable, and every number is checked against the
# real page range before it is used.
class PageRouter
  MODEL = "claude-haiku-4-5".freeze
  MAX_PAGES = 12
  MAX_TOKENS = 300

  # Pages that exist to point elsewhere (both indices) or carry no substance
  # (title page, contents). Retrieving them wastes tokens and tells the reader
  # nothing, so they are never valid answer sources.
  NON_CONTENT_PAGES = ((1..2).to_a + (5..8).to_a + (240..254).to_a).freeze

  SYSTEM = <<~PROMPT.freeze
    You are a retrieval index for "The Practice of the Free Church of Scotland"
    (the Blue Book), #{BlueBook::EDITION}.

    You will be given the book's contents outline and its two indices, then a
    user's question. Your only job is to choose which printed pages should be
    read in order to answer that question. You never answer the question itself.

    Rules:
    - Reply with page numbers only: comma-separated integers, nothing else.
      Example: 44, 45, 46, 149
    - Choose at most #{MAX_PAGES} pages. Prefer precision, but when a topic
      plainly runs across a page break, include the adjacent page.
    - Use the indices as your primary guide. Sub-entries are nested under their
      main entry, and every number is a printed page number.
    - Include pages from the Appendices when they carry the relevant Act, form
      of process, or specimen minute.
    - Never return pages from the indices themselves (240-254) or the contents
      (5-8); they point elsewhere rather than containing the substance.
    - If the question is unrelated to Free Church practice or polity, reply with
      the single word: NONE

    --- BEGIN BOOK ROUTING TABLE ---
    %{routing_table}
    --- END BOOK ROUTING TABLE ---
  PROMPT

  Result = Struct.new(:pages, :usage, keyword_init: true) do
    def none? = pages.empty?
  end

  def initialize(client: Anthropic::Client.new)
    @client = client
  end

  def call(question)
    response = @client.messages.create(
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system_: format(SYSTEM, routing_table: BlueBook.routing_table),
      messages: [ { role: "user", content: question } ]
    )

    Result.new(pages: parse(text_of(response)), usage: response.usage)
  end

  private

  def text_of(response)
    response.content.filter_map { |block| block.text if block.type == :text }.join(" ")
  end

  # Trust nothing: pull integers out, discard anything that isn't a real
  # content page, and cap the count so a malformed reply can't blow the budget.
  def parse(text)
    return [] if text.match?(/\bNONE\b/i)

    text.scan(/\d+/)
        .map(&:to_i)
        .uniq
        .select { |page| BlueBook::PAGE_RANGE.cover?(page) }
        .reject { |page| NON_CONTENT_PAGES.include?(page) }
        .select { |page| BlueBook.page(page).present? }
        .sort
        .first(MAX_PAGES)
  end
end
