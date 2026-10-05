# blue-bot

Ask questions of _The Practice of the Free Church of Scotland_ — the Blue Book —
and get answers cited to the printed page.

Rails API + React frontend, deployed as a single container on Railway.

**The book itself is not in this repo.** It is copyrighted by the Free Church
of Scotland, so its extracted text lives in a separate private repo
(`jray89/blue-bot-corpus`) and is loaded at boot. Everything here — the code,
the prompts, the tests — is original work and runs without it: the test suite
uses a small synthetic corpus about teapots and lighthouses.

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
data/       Where a local clone of the private corpus goes. Gitignored.
script/     One-time build tools that produce the corpus.
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

`data/blue-book/` is a checkout of the private corpus repo, so publish a
rebuild from there: commit, tag (`v2`, …), push, then point
`BLUE_BOOK_CORPUS_REF` at the new tag.

## The corpus

The corpus repo's root is exactly the corpus directory: `manifest.json`,
`routing_table.md`, `indices.md` and `pages/p001.md` … `p254.md`. The app reads
it from `BLUE_BOOK_DATA_DIR`, or, when that is unset, from `data/blue-book/` at
the repo root.

- **Locally**, clone it into place (needs access to the private repo):

  ```sh
  git clone git@github.com:jray89/blue-bot-corpus data/blue-book
  ```

  or fetch a tagged snapshot with a token instead of SSH:

  ```sh
  BLUE_BOOK_CORPUS_TOKEN=github_pat_… BLUE_BOOK_DATA_DIR=data/blue-book backend/bin/fetch-corpus
  ```

  Without a corpus, development still boots (with a warning) but cannot answer.

- **In the container**, `bin/docker-entrypoint` runs `bin/fetch-corpus` before
  Rails starts. If `$BLUE_BOOK_DATA_DIR/manifest.json` already exists it does
  nothing; otherwise it downloads the `BLUE_BOOK_CORPUS_REF` tarball from the
  GitHub API using `BLUE_BOOK_CORPUS_TOKEN`, checks it has a manifest, routing
  table and pages, and moves it into place. Production refuses to boot without
  a corpus, so a bad token fails the `/up` healthcheck rather than serving
  broken answers.

  The token is a **runtime** variable only. It is never a build arg (those are
  recorded in image history), never echoed, and never on a command line. The
  image contains no book text, and `data/` is excluded from the build context.

The token should be a fine-grained personal access token scoped to the corpus
repo alone with **Contents: Read-only** — see [Deploying](#deploying).

## Development

```sh
git clone git@github.com:jray89/blue-bot-corpus data/blue-book   # see above
cp backend/.env.example backend/.env    # then put your real key in it
cd backend  && bundle install && bin/rails s     # :3000
cd frontend && pnpm install   && pnpm dev        # :5175, proxies /api to :3000
```

The key must live in **`backend/.env`**, not the repo root — `dotenv-rails` only
reads the Rails app root. Both are gitignored and dockerignored, but only
`backend/.env` is actually loaded.

In production there is no `.env` file at all: Railway injects the environment
variables directly, and `.dockerignore` keeps any local one out of the image.

## Tests

```sh
cd backend  && bin/rails test        # no corpus, API key or network needed
cd backend  && bin/rubocop && bin/brakeman
cd frontend && pnpm typecheck && pnpm build
```

The suite runs against a synthetic fixture corpus in
`backend/test/fixtures/files/blue-book/` (invented text — none of it is from
the book), which `test/test_helper.rb` selects via `BLUE_BOOK_DATA_DIR`. Every
Anthropic client is a fake; constructing a real one in a test raises, so the
suite can never spend money. It covers corpus loading, page routing, citation
verification, the daily spend cap, per-IP throttling, and the SSE endpoint end
to end. CI (`.github/workflows/ci.yml`) runs all of the above on every push
and pull request.

## Configuration

| Variable                 | Default                  | Notes                                                                  |
| ------------------------ | ------------------------ | ---------------------------------------------------------------------- |
| `ANTHROPIC_API_KEY`      | —                        | Required.                                                              |
| `SECRET_KEY_BASE`        | —                        | Required in production. Generate with `bin/rails secret`.              |
| `BLUE_BOOK_CORPUS_TOKEN` | —                        | Required in production. Read-only token for the private corpus repo.   |
| `BLUE_BOOK_CORPUS_REF`   | `v1`                     | Tag (or branch/SHA) of the corpus repo to download.                    |
| `BLUE_BOOK_CORPUS_REPO`  | `jray89/blue-bot-corpus` | Corpus repo, `owner/name`.                                             |
| `BLUE_BOOK_DATA_DIR`     | `data/blue-book`         | Set by the Dockerfile to `/rails/data/blue-book`. Authoritative if set. |
| `DAILY_QUESTION_LIMIT`   | `16`                     | Global hard cap. ~$0.04/question → ~$20/month.                         |
| `RAILS_MAX_THREADS`      | `12`                     | Bounds concurrent askers; each SSE stream holds a thread.              |
| `ALLOWED_ORIGINS`        | localhost dev ports      | Comma separated. Not needed in production.                             |

The app does not use Rails encrypted credentials; there is no `master.key`.

## Deploying

Railway builds the root `Dockerfile` (see `railway.json`). Set
`ANTHROPIC_API_KEY`, `SECRET_KEY_BASE` and `BLUE_BOOK_CORPUS_TOKEN` as service
variables, and `BLUE_BOOK_CORPUS_REF` if you want something other than `v1`.

To create the corpus token: GitHub → Settings → Developer settings → Personal
access tokens → **Fine-grained tokens** → Generate new token. Resource owner:
your account; Repository access: **Only select repositories** →
`blue-bot-corpus`; Repository permissions: **Contents: Read-only** (Metadata:
Read-only is added automatically); nothing else. Pick an expiry and note it —
when the token expires the next deploy or restart will fail its healthcheck
until it is replaced.

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
- **No book text in this repo.** The book is copyrighted by the Free Church of
  Scotland: the PDF is gitignored, the extracted corpus lives in a private repo
  fetched at boot, and the answering prompt is instructed to quote sparingly
  and paraphrase otherwise.

## Known limitations

- Three official **errata** (pp. 59, 114, 157) ship as their own section of the
  routing table so the model doesn't quote a reference the Church has corrected.
- Citations are produced as inline `(p. N)` text and **verified server-side**
  against the pages actually supplied; any page the model invents is reported to
  the frontend and flagged to the reader. Moving to the Anthropic Citations API
  would give character-level provenance and is the obvious next upgrade.
