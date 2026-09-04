# Serves the built React app for any non-API path, so client-side routing works
# and a deep link doesn't 404. The frontend is compiled into public/ during the
# Docker build (see Dockerfile).
class FallbackController < ApplicationController
  def index
    index_path = Rails.public_path.join("index.html")

    if File.exist?(index_path)
      # index.html must never be cached. It names the hashed asset bundles, and
      # those hashes change on every deploy — a browser holding a stale shell
      # would request a bundle that no longer exists and render nothing. The
      # hashed assets themselves are immutable and cache freely.
      response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"

      send_file index_path, type: "text/html", disposition: "inline"
    else
      render json: {
        error: "Frontend not built. Run `pnpm build` in frontend/ and copy dist/ into backend/public/."
      }, status: :not_found
    end
  end
end
