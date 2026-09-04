require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
# require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # No database, no job queue, no cache server. The Blue Book corpus is read
    # from disk at boot and the only mutable state is SpendGuard's in-process
    # counter, so there is nothing to persist and nothing to connect to.
    config.cache_store = :null_store

    # Origins permitted to call /api/* cross-origin. In production the frontend
    # is served from this same origin, so this only matters for `pnpm dev` and
    # any additional origin named in ALLOWED_ORIGINS (comma separated).
    config.x.allowed_origins = ENV.fetch("ALLOWED_ORIGINS", "http://localhost:5173,http://localhost:5174")
                                  .split(",")
                                  .map(&:strip)
                                  .reject(&:empty?)

    # ActionDispatch::Static answers "/" with public/index.html before routing
    # ever happens, which means FallbackController never runs and the SPA shell
    # goes out with no Cache-Control. A browser can then hold a stale shell
    # pointing at an asset hash that no longer exists after a deploy, and render
    # nothing. Pointing index_name at a file that doesn't exist lets "/" fall
    # through to the controller, which sets no-cache explicitly.
    #
    # Hashed assets under /assets/ are still served by the static middleware and
    # are content-addressed, so caching them is safe either way.
    config.public_file_server.index_name = "__spa_shell_is_served_by_rails"

    # Streaming responses must not be buffered or transformed on the way out.
    # Rack::ETag buffers the whole body to hash it, which would defeat SSE
    # entirely; the deflater would hold it for compression.
    config.middleware.delete Rack::ETag
    config.middleware.delete Rack::ConditionalGet
  end
end
