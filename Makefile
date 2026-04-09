.PHONY: setup compile test lint bench bench-record clean ci

# All commands run inside nix develop
NIX := nix develop -c

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

bench: compile
	$(NIX) bundle exec ruby bench/puma_compare.rb

bench-record: compile
	$(NIX) bundle exec rake bench:record_run

clean:
	$(NIX) bundle exec rake clobber
	$(NIX) cargo clean --manifest-path ext/gte/Cargo.toml

ci: lint test
