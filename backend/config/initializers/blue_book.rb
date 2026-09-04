# Load the Blue Book corpus at boot rather than on first request.
#
# Two reasons: the first asker shouldn't pay to read 254 files, and a missing or
# malformed corpus should break the healthcheck immediately instead of surfacing
# as a mid-stream error after we've already charged the day's budget.
Rails.application.config.after_initialize do
  BlueBook.preload!
  Rails.logger.info("Blue Book loaded: #{BlueBook.page_count} pages, #{BlueBook::EDITION}")
rescue BlueBook::MissingCorpus => e
  message = "Blue Book corpus unavailable: #{e.message}. " \
            "Run script/extract_blue_book.py and script/build_routing_table.py."

  # In production this app cannot do its job without the corpus, so refuse to
  # boot and let the healthcheck fail loudly. In development, warn and carry on
  # so the rest of the app is still workable.
  raise message if Rails.env.production?

  Rails.logger.warn(message)
end
