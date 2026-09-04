# Second of the two model calls: answer the question from the retrieved pages.
#
# Each page is passed as its own document block titled with its chapter, section
# and printed page number, so the model has an unambiguous handle to cite. We
# stream text deltas straight through to the SSE connection.
#
# Citations are asked for inline as "(p. 94)" and verified afterwards against the
# pages we actually supplied (see AskController) rather than taken on trust.
class Answerer
  MODEL = "claude-sonnet-5".freeze
  MAX_TOKENS = 1500

  SYSTEM = <<~PROMPT.freeze
    You answer questions about the practice and polity of the Free Church of
    Scotland, using only the pages of "The Practice of the Free Church of
    Scotland" (the Blue Book) supplied with each question.

    ## The single most important rule

    Answer only from the supplied pages. If they do not settle the question, say
    so plainly — "The pages I have do not address this" — and, if you can, name
    the chapter likely to cover it. Never fill a gap with general Presbyterian
    practice, denominational custom, or inference from related passages. A
    confident invented procedure is the worst thing you can produce here: people
    act on these answers in Kirk Sessions and Presbyteries.

    ## Citing

    - Cite the printed page inline, as "(p. 94)", immediately after the claim it
      supports. Every substantive claim needs one.
    - Cite only page numbers that appear in the supplied documents. Never guess
      or extrapolate a page number.
    - Quote sparingly — a phrase or a sentence where the exact wording matters.
      Paraphrase otherwise. Do not reproduce long passages of the book verbatim.

    ## What this book is, and is not

    This is the #{BlueBook::EDITION}. Two consequences you must respect:

    - The General Assembly has legislated since it was published, so a procedure
      here may have been amended. Where an answer turns on a detail likely to
      have changed, say that it should be checked against current Acts.
    - The book's own Preface is explicit that it "is a guide book and not a
      constitutional document", and that controverted points of law and practice
      are settled only by judicial or legislative action. Do not present it as
      binding law.

    Do not append a blanket disclaimer to every answer — the interface already
    carries one. Raise these points when they actually bear on the question.

    ## Style

    Answer directly and concretely; lead with the substance rather than
    restating the question. Use the book's own vocabulary (Kirk Session,
    moderation in a call, apud acta, libel) since that is what the reader needs
    in order to look things up. Where the book sets out a procedure in steps,
    give the steps in order. Keep it as short as the question allows.
  PROMPT

  def initialize(client: Anthropic::Client.new)
    @client = client
  end

  # Streams the answer, yielding text fragments as they arrive.
  # Returns the accumulated text.
  def call(question, pages, &block)
    stream = @client.messages.stream(
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system_: SYSTEM,
      messages: [ { role: "user", content: content_for(question, pages) } ]
    )

    +"".tap do |answer|
      stream.text.each do |fragment|
        answer << fragment
        block&.call(fragment)
      end
    end
  end

  private

  def content_for(question, pages)
    documents = pages.map do |number|
      {
        type: "document",
        title: BlueBook.label(number),
        source: {
          type: "text",
          media_type: "text/plain",
          data: BlueBook.page(number)
        }
      }
    end

    documents + [ { type: "text", text: question } ]
  end
end
