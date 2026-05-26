FROM ruby:3.4-slim AS gte-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential curl ca-certificates libomp-dev libssl-dev libclang-dev pkg-config \
  && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain stable --profile minimal --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /build

COPY gte.gemspec VERSION Gemfile Rakefile Makefile rust-toolchain.toml Cargo.toml Cargo.lock ./
COPY lib/ ./lib/
COPY ext/ ./ext/

RUN bundle config set --local without development test
RUN bundle install --jobs 4 --retry 3
RUN bundle exec rake compile

FROM ruby:3.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libyaml-dev libomp-dev curl ca-certificates wrk \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=gte-builder /build /gte

COPY bench/rails/app/Gemfile ./
RUN bundle config set --local without development test
RUN bundle install --jobs 4 --retry 3

COPY bench/rails/app/ .

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV MIN_THREADS=2
ENV MAX_THREADS=5
ENV WEB_CONCURRENCY=0

EXPOSE 3000

HEALTHCHECK --interval=2s --timeout=3s --retries=15 \
  CMD curl -sf http://localhost:3000/health || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "-e", "production"]
