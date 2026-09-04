# blue-bot

Ask questions of *The Practice of the Free Church of Scotland* — the Blue Book —
and get answers cited to the printed page.

Rails API + React frontend, deployed as a single container on Railway.

## How it answers

The book is ~254 pages / ~170k tokens. That fits in a single request, but sending
it every time would cost ~$0.56 a question, and prompt caching doesn't rescue a
low-traffic public app because the cache is almost never warm. So each question
takes two calls:

1. **Route** — Haiku 4.5 reads the book's own contents outline and its two
   indices (~7.6k tokens) and picks the handful of printed pages worth reading.
   The General Index is a retrieval map written by people who know the subject,
   which beats anything we'd get from chunking or embeddings.
2. **Answer** — Sonnet 5 receives only those pages, each as its own document
   block titled with chapter, section and page number, and streams the answer
   back over SSE.

**Measured at $0.034 a question** over the sample set (`bin/rails ask:batch`),
against ~$0.95 for the whole book on Sonnet — roughly 28x cheaper. Routing is a
flat $0.0104; answering adds $0.016–$0.031 depending on how many pages the
question needs. Out-of-scope questions cost the routing call only, because the
answering model is never invoked.

At $20/month that is ~19 questions a day; `DAILY_QUESTION_LIMIT` defaults to 16
to leave headroom.

Inspect routing quality — the thing that drives both answer quality and cost,
and which is invisible from the UI — with:

```sh
bin/rails ask:one Q="How is a minister called?"   # one question, streamed
bin/rails ask:batch                               # sample set + cost summary
```

Page numbers are trustworthy: the PDF's pagination was aligned to the printed
book, so a citation of "p. 94" can be checked against a physical copy.

## Layout

```
backend/    Rails 8 API. No database — the corpus loads into memory at boot.
frontend/   Vite + React + Tailwind 4 + shadcn conventions.
data/       Extracted corpus, committed. The PDF itself is never committed.
script/     One-time build tools that produce data/.
```

## Rebuilding the corpus

Only needed for a new edition of the book. Requires `pdftotext` (poppler) and
Python with `PyPDF2`.

```sh
python3 script/extract_blue_book.py path/to/the-practice.pdf
python3 script/extract_index.py      path/to/the-practice.pdf
python3 script/build_routing_table.py
```

This produces `data/blue-book/`: 254 per-page markdown files, a page→chapter
manifest, the structured indices, and the routing table. If the page ranges in
`STRUCTURE` (in `extract_blue_book.py`) don't match the new edition's Contents,
update them first — they drive the citation labels.

## Development

```sh
cp backend/.env.example backend/.env    # then put your real key in it
cd backend  && bundle install && bin/rails s     # :3000
cd frontend && pnpm install   && pnpm dev        # :5175, proxies /api to :3000
```

The key must live in **`backend/.env`**, not the repo root — `dotenv-rails` only
reads the Rails app root. Both are gitignored and dockerignored, but only
`backend/.env` is actually loaded.

In production there is no `.env` file at all: Railway injects the environment
variables directly, and `.dockerignore` keeps any local one out of the image.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `ANTHROPIC_API_KEY` | — | Required. |
| `SECRET_KEY_BASE` | — | Required in production. |
| `DAILY_QUESTION_LIMIT` | `16` | Global hard cap. ~$0.04/question → ~$20/month. |
| `RAILS_MAX_THREADS` | `12` | Bounds concurrent askers; each SSE stream holds a thread. |
| `ALLOWED_ORIGINS` | localhost dev ports | Comma separated. Not needed in production. |
| `BLUE_BOOK_DATA_DIR` | auto-detected | Set by the Dockerfile to `/rails/data/blue-book`. |

## Cost controls

The endpoint is public, so spend is bounded in three places. The first two live
in this repo; the third is the only real guarantee.

1. **Per-IP throttling** (`config/initializers/rack_attack.rb`) — 5/hour,
   15/day, plus a burst limit so one client can't pin every Puma thread with
   concurrent streams.
2. **Global daily cap** (`app/services/spend_guard.rb`) — an in-process counter,
   because per-IP limits can't bound the number of IPs. It resets on restart and
   counts requests rather than billed tokens.
3. **A spend limit in the Anthropic Console.** ← set this. Neither of the above
   survives a restart loop or an unexpectedly expensive request.

## Gemfile.lock has no CHECKSUMS block — on purpose

Bundler derives checksums from gems it actually downloads. Resolving on macOS
therefore leaves empty entries for the Linux-only binaries (`nokogiri`,
`thruster`), and the Docker build runs `BUNDLE_DEPLOYMENT=1`, which refuses to
proceed with an incomplete CHECKSUMS block:

```
Your lockfile has an empty CHECKSUMS entry for "nokogiri", but can't be updated
because frozen mode is set
```

`bundle lock --add-checksums` does not fix it — it cannot fetch checksums for
platforms it will never install. The block is removed instead; versions and
platforms remain pinned. If a future Bundler reintroduces it, strip it again and
verify with:

```sh
cd backend && BUNDLE_FROZEN=true BUNDLE_DEPLOYMENT=1 bundle install
```

## Deliberate constraints

- **No database.** Single-turn, nothing persisted. The corpus is read-only and
  lives in memory; the only mutable state is the daily counter.
- **Puma runs in single mode** (`workers 0`). The daily counter and Rack::Attack's
  throttle counters are both in-process, so a second worker would mean a second
  set of counters and double the intended cap. Move both to a shared store
  before adding workers.
- **The repo is private and the PDF is gitignored.** The book is copyrighted by
  the Free Church of Scotland; the answering prompt is instructed to quote
  sparingly and paraphrase otherwise.

## Known limitations

- The corpus is the **Eighth Edition (Revised), 1995**. The General Assembly has
  legislated since, so a procedure described here may have been amended. There
  is deliberately **no standing notice in the UI**; the caveat is carried by the
  answering prompt, which is instructed to flag anything turning on a detail
  likely to have changed and to state that the book "is a guide book and not a
  constitutional document". If the app is ever shared widely, reconsider whether
  that is enough on its own.
- Three official **errata** (pp. 59, 114, 157) ship as their own section of the
  routing table so the model doesn't quote a reference the Church has corrected.
- Citations are produced as inline `(p. N)` text and **verified server-side**
  against the pages actually supplied; any page the model invents is reported to
  the frontend and flagged to the reader. Moving to the Anthropic Citations API
  would give character-level provenance and is the obvious next upgrade.
