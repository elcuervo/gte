.PHONY: setup compile test lint bench bench-memory bench-record clean ci models

# All commands run inside nix develop
NIX := nix develop -c

# Model directories for benchmarks
export GTE_MODEL_DIR  := $(CURDIR)/models/e5
export GTE_CLIP_DIR   := $(CURDIR)/models/clip
export GTE_SIGLIP2_DIR := $(CURDIR)/models/siglip2

setup:
	$(NIX) bundle install --jobs 4 --retry 3

compile:
	$(NIX) bundle exec rake compile

test: compile
	$(NIX) cargo test --manifest-path ext/gte/Cargo.toml --no-default-features
	$(NIX) bundle exec rspec

lint:
	$(NIX) cargo clippy --manifest-path ext/gte/Cargo.toml --no-default-features -- -D warnings
	$(NIX) bundle exec rubocop

models:
	@script/download-models

bench: compile models
	$(NIX) bundle exec ruby bench/puma_compare.rb

bench-memory: compile models
	$(NIX) bundle exec ruby bench/memory_probe.rb --compare-pure

bench-record: compile
	$(NIX) bundle exec rake bench:record_run

clean:
	$(NIX) bundle exec rake clobber
	$(NIX) cargo clean --manifest-path ext/gte/Cargo.toml

ci: lint test
