# Diagnostic endpoint for proxy buffering. Costs nothing to call — no model
# calls, no corpus access — so it can be hit repeatedly while working out
# whether an edge proxy is holding streamed responses.
#
# Emits `count` frames one second apart, each carrying the server-side elapsed
# time. If the client sees the frames arrive one second apart, streaming works
# end to end. If they all land together at the end, something between the app
# and the client is buffering.
#
# Bounded deliberately: at most 10 frames, so a caller cannot hold a Puma thread
# open indefinitely. Remove once the buffering question is settled.
class StreamTestController < ApplicationController
  include ActionController::Live

  MAX_FRAMES = 10

  def show
    count = params.fetch(:count, 5).to_i.clamp(1, MAX_FRAMES)
    padding_kb = params.fetch(:padding_kb, 0).to_i.clamp(0, 256)

    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    started = Time.now

    response.stream.write(": #{'x' * (padding_kb * 1024)}\n\n") if padding_kb.positive?

    count.times do |i|
      response.stream.write("event: tick\n")
      response.stream.write(
        "data: #{{ i: i, elapsed: (Time.now - started).round(3) }.to_json}\n\n"
      )
      sleep 1
    end

    response.stream.write("event: done\n")
    response.stream.write("data: #{{ elapsed: (Time.now - started).round(3) }.to_json}\n\n")
  rescue ActionController::Live::ClientDisconnected
    # Caller went away mid-test; nothing to do.
  ensure
    response.stream.close
  end
end
