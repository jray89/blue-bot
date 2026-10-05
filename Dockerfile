# syntax=docker/dockerfile:1
# check=error=true
#
# Build context is the repository root, because the image needs two things:
#   backend/  the Rails API
#   frontend/ the React app, compiled into backend's public/
#
# The Blue Book corpus is NOT in the image. It is copyrighted, lives in a
# private repo, and is downloaded at container start by bin/docker-entrypoint
# (see bin/fetch-corpus) using the runtime-only BLUE_BOOK_CORPUS_TOKEN. Never
# pass that token as a build arg: build args are recorded in the image history.

ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# curl (plus tar/gzip, which are Essential in Debian and always present) is
# also what bin/fetch-corpus uses at runtime.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl libjemalloc2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    BLUE_BOOK_DATA_DIR="/rails/data/blue-book"

RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

# ---------------------------------------------------------------- build stage
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g pnpm@9 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Gems first so a frontend-only change doesn't invalidate the bundle layer.
COPY backend/Gemfile backend/Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

# Frontend: install against the lockfile, then build.
COPY frontend/package.json frontend/pnpm-lock.yaml* /frontend/
RUN cd /frontend && pnpm install --frozen-lockfile
COPY frontend/ /frontend/
RUN cd /frontend && pnpm run build

COPY backend/ .

# The React build is served by Rails (see FallbackController).
RUN cp -r /frontend/dist/* public/

RUN bundle exec bootsnap precompile -j 1 app/ lib/

# ---------------------------------------------------------------- final stage
FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# bin/fetch-corpus writes the corpus to $BLUE_BOOK_DATA_DIR (/rails/data/blue-book)
# as the non-root user, staging it in the parent directory first.
RUN mkdir -p /rails/data && chown rails:rails /rails/data

USER 1000:1000

# Fetches the corpus (if not already present), then execs CMD.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 8080
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:8080", "-e", "production"]
