# Single-turn question endpoint, streamed over Server-Sent Events.
#
# Nothing is persisted: no conversation, no history, no database. One question
# in, one streamed answer out.
#
# Note that ActionController::Live holds a Puma thread for the whole life of the
# stream, so RAILS_MAX_THREADS bounds concurrent askers. See config/puma.rb.
class AskController < ApplicationController
  include ActionController::Live

  MAX_QUESTION_LENGTH = 500

  def create
    question = params[:question].to_s.strip
    return render_error(:bad_request, "Please ask a question.") if question.empty?

    if question.length > MAX_QUESTION_LENGTH
      return render_error(:bad_request, "Questions are limited to #{MAX_QUESTION_LENGTH} characters.")
    end

    begin
      SpendGuard.consume!
    rescue SpendGuard::LimitExceeded
      return render_error(
        :too_many_requests,
        "This service has reached its daily question limit. Please try again tomorrow."
      )
    end

    stream_answer(question)
  end

  # Lets the frontend show remaining capacity without spending anything.
  def status
    render json: SpendGuard.status.merge(
      edition: BlueBook::EDITION,
      pages: BlueBook.page_count,
      per_visitor: Rack::Attack::PER_VISITOR_LIMITS
    )
  end

  private

  def stream_answer(question)
    prepare_stream!
    spent = false

    routed = PageRouter.new.call(question)

    if routed.none?
      # Out of scope, or the indices had nothing. Nothing was spent on Sonnet,
      # so hand the reservation back rather than charging the day's budget.
      SpendGuard.refund!
      emit(:no_answer, message: "The Blue Book's indices don't point to anything " \
                                "covering this.")
      return
    end

    spent = true
    emit(:sources, sources: routed.pages.map { |page| source_for(page) })

    answer = Answerer.new.call(question, routed.pages) do |fragment|
      emit(:token, text: fragment)
    end

    emit(:done, unverified_citations: CitationVerifier.unverified(answer, routed.pages))
  rescue ActionController::Live::ClientDisconnected
    # Reader closed the tab. Already charged; nothing useful left to say.
    Rails.logger.info("ask abandoned by client")
  rescue Anthropic::Errors::RateLimitError
    SpendGuard.refund! unless spent
    emit(:error, message: "The service is briefly rate limited. Please try again in a moment.")
  rescue StandardError => e
    # Once headers are sent the status code is already 200, so an error can only
    # be reported in-band. Log the detail; tell the user something useful.
    SpendGuard.refund! unless spent
    Rails.logger.error("ask failed: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    emit(:error, message: "Something went wrong while answering. Please try again.")
  ensure
    # A leaked stream leaks a Puma thread permanently.
    response.stream.close
  end

  def prepare_stream!
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    # Tell nginx-style proxies not to buffer.
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Last-Modified"] = Time.now.httpdate
  end

  def emit(event, **payload)
    response.stream.write("event: #{event}\n")
    response.stream.write("data: #{payload.to_json}\n\n")
  rescue IOError, Errno::EPIPE
    # Client hung up mid-answer; unwind quietly.
    raise ActionController::Live::ClientDisconnected
  end

  def source_for(page)
    {
      page: page,
      chapter: BlueBook.chapter(page),
      label: BlueBook.label(page)
    }
  end

  def render_error(status, message)
    render json: { error: message }, status: status
  end
end
