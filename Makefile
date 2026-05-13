.PHONY: setup compile test lint bench bench-memory bench-record clean ci models

# All commands run inside nix develop
NIX := nix develop -c
BUNDLE_ENV := env \
	BUNDLE_DISABLE_SHARED_GEMS=1 \
	GEM_HOME=$(CURDIR)/.bundle-gems \
	GEM_PATH=$(CURDIR)/.bundle-gems \
	BUNDLE_PATH=$(CURDIR)/vendor/bundle

# Model directories for benchmarks
export GTE_MODEL_DIR  := $(CURDIR)/models/e5
export GTE_CLIP_DIR   := $(CURDIR)/models/clip
export GTE_SIGLIP2_DIR := $(CURDIR)/models/siglip2

setup:
	$(NIX) $(BUNDLE_ENV) bundle install --jobs 4 --retry 3

compile:
	$(NIX) $(BUNDLE_ENV) bundle exec rake compile

test: compile
	$(NIX) cargo test --manifest-path ext/gte/Cargo.toml --no-default-features
	$(NIX) $(BUNDLE_ENV) bundle exec rspec

lint:
	$(NIX) cargo clippy --manifest-path ext/gte/Cargo.toml --no-default-features -- -D warnings
	$(NIX) $(BUNDLE_ENV) bundle exec rubocop -A

models:
	@script/download-models

bench: setup compile models
	$(NIX) $(BUNDLE_ENV) bundle exec ruby bench/puma_compare.rb

bench-memory: setup compile models
	$(NIX) $(BUNDLE_ENV) bundle exec ruby bench/memory_probe.rb --compare-pure

bench-record: setup compile models
	$(NIX) $(BUNDLE_ENV) bundle exec rake bench:record_run

clean:
	$(NIX) $(BUNDLE_ENV) bundle exec rake clobber
	$(NIX) cargo clean --manifest-path ext/gte/Cargo.toml
	rm -rf .bundle-gems vendor/bundle

ci: lint test
