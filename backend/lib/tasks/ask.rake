# Diagnostics for the two-call pipeline.
#
# Routing quality is the thing that decides both answer quality and cost, and it
# is invisible from the UI — you only see the answer, not which pages were read.
# These tasks surface it.
#
#   bin/rails ask:one Q="How is a minister called?"   # one question, full trace
#   bin/rails ask:batch                               # the standard sample set
#
# Both spend real money. `ask:batch` is roughly $0.03 per question.
namespace :ask do
  SAMPLE = [
    "What censures may a Kirk Session impose?",
    "How is a minister called to a vacant congregation?",
    "Who is entitled to sit and vote in a Presbytery?",
    "What is the procedure for a dissent and complaint?",
    "What form of citation is used in a case of discipline?",
    "How are the funds of a congregation administered?",
    # Should be answered with "the pages I have do not address this" rather
    # than invention — the book predates the question.
    "What is the policy on livestreaming a service to social media?",
    # Should route to NONE and never reach the answering model at all.
    "What is the best recipe for Scotch broth?"
  ].freeze

  desc "Trace one question end to end. Q=... to set the question."
  task one: :environment do
    question = ENV["Q"].presence or abort("usage: bin/rails ask:one Q=\"your question\"")
    trace(question, stream: true)
  end

  desc "Run the sample question set and summarise routing and cost."
  task batch: :environment do
    results = SAMPLE.map { |question| trace(question, stream: false) }

    puts "=" * 78
    puts format("%-52s %6s %7s %7s", "QUESTION", "PAGES", "TOKENS", "COST")
    puts "-" * 78
    results.each do |r|
      puts format(
        "%-52s %6s %7d %7s",
        r[:question][0, 50],
        r[:pages].empty? ? "NONE" : r[:pages].size,
        r[:tokens],
        "$#{'%.4f' % r[:cost]}"
      )
    end
    puts "-" * 78

    answered = results.reject { |r| r[:pages].empty? }
    total = results.sum { |r| r[:cost] }
    mean = answered.empty? ? 0 : total / answered.size
    fabricated = results.sum { |r| r[:fabricated].size }

    puts format("answered           : %d of %d", answered.size, results.size)
    puts format("mean cost/question : $%.4f", mean)
    puts format("implied at $20/mo  : ~%d questions (~%d/day)", (20 / mean), (20 / mean / 30)) if mean.positive?
    puts format("fabricated citations: %d  %s", fabricated, fabricated.zero? ? "OK" : "<<< INVESTIGATE")
    puts "=" * 78
  end

  # Pricing per 1M tokens, for the models in PageRouter/Answerer.
  HAIKU_IN, HAIKU_OUT = 1.0, 5.0
  SONNET_IN, SONNET_OUT = 3.0, 15.0

  def trace(question, stream:)
    puts "\n#{'=' * 78}\nQ: #{question}\n#{'-' * 78}"

    routed = PageRouter.new.call(question)
    route_cost = (routed.usage.input_tokens * HAIKU_IN + routed.usage.output_tokens * HAIKU_OUT) / 1_000_000.0

    if routed.none?
      puts "ROUTED: NONE (out of scope — answering model never called)"
      puts format("cost: $%.4f (routing only)", route_cost)
      return { question: question, pages: [], tokens: routed.usage.input_tokens, cost: route_cost, fabricated: [] }
    end

    routed.pages.each { |p| puts "  p.#{p}  #{BlueBook.label(p)}" }

    context = routed.pages.sum { |p| BlueBook.page(p).length } / 4
    answer = Answerer.new.call(question, routed.pages) { |f| print f if stream }
    puts if stream

    unless stream
      first = answer.split(/(?<=\.)\s/).first(2).join(" ")
      puts "  -> #{first[0, 160]}#{'...' if first.length > 160}"
    end

    out_tokens = answer.length / 4
    answer_cost = ((context + 700) * SONNET_IN + out_tokens * SONNET_OUT) / 1_000_000.0

    cited = answer.scan(/\(p\.\s*(\d{1,3})\)/).flatten.map(&:to_i).uniq
    fabricated = cited - routed.pages
    puts "  fabricated citations: #{fabricated.inspect}" unless fabricated.empty?
    puts format("  cost: $%.4f (route $%.4f + answer $%.4f)", route_cost + answer_cost, route_cost, answer_cost)

    {
      question: question,
      pages: routed.pages,
      tokens: routed.usage.input_tokens + context,
      cost: route_cost + answer_cost,
      fabricated: fabricated
    }
  end
end
