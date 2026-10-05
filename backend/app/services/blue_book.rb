# Loads the extracted Blue Book corpus into memory once, at boot.
#
# The whole book is ~680KB of text across 254 files, so holding it resident is
# cheaper and simpler than any storage layer — which is why this app has no
# database at all. Everything here is read-only after boot.
#
# The corpus is produced by the scripts in script/ but, being the text of a
# copyrighted book, is not committed here. It lives in a private repo
# (jray89/blue-bot-corpus): developers clone it into data/blue-book, and the
# container downloads it at start (bin/fetch-corpus). The PDF itself is never
# shipped or read at runtime.
class BlueBook
  EDITION = "Eighth Edition (Revised), 1995".freeze
  PAGE_RANGE = (1..254).freeze

  class MissingCorpus < StandardError; end

  class << self
    # Resolved once. In development the corpus is cloned to the repo root next
    # to backend/; in the container bin/fetch-corpus puts it in /rails/data; the
    # test suite points BLUE_BOOK_DATA_DIR at a synthetic fixture.
    def root
      @root ||= begin
        candidates = [
          ENV["BLUE_BOOK_DATA_DIR"],
          Rails.root.join("data", "blue-book").to_s,
          Rails.root.join("..", "data", "blue-book").to_s
        ].compact

        found = candidates.find { |path| File.directory?(path) }
        raise MissingCorpus, "no Blue Book corpus in: #{candidates.join(', ')}" if found.nil?

        Pathname.new(found).cleanpath
      end
    end

    # The contents outline plus both indices — what the router reasons over.
    def routing_table
      @routing_table ||= read!("routing_table.md")
    end

    def manifest
      @manifest ||= JSON.parse(read!("manifest.json")).fetch("pages")
    end

    # Text of a single printed page, or nil if it is blank/out of range.
    def page(number)
      return nil unless PAGE_RANGE.cover?(number)

      pages[number]
    end

    # Human-readable provenance for a page, e.g.
    # "Chapter V: Discipline — Part III: Processes — Kirk Session, p.94"
    def label(number)
      entry = manifest[number.to_s]
      return "p.#{number}" if entry.nil?

      "#{entry['chapter']} — #{entry['section']}, p.#{number}"
    end

    def chapter(number)
      manifest.dig(number.to_s, "chapter")
    end

    # Warm every lazily-loaded attribute so the first request doesn't pay for
    # it, and so a broken corpus fails at boot rather than mid-stream.
    def preload!
      routing_table
      manifest
      pages
      self
    end

    def page_count
      pages.count { |_, text| text.present? }
    end

    private

    def pages
      @pages ||= PAGE_RANGE.each_with_object({}) do |number, acc|
        path = root.join("pages", format("p%03d.md", number))
        next unless File.exist?(path)

        text = File.read(path).strip
        acc[number] = text if text.present?
      end.freeze
    end

    def read!(filename)
      path = root.join(filename)
      raise MissingCorpus, "missing #{path}" unless File.exist?(path)

      File.read(path)
    end
  end
end
