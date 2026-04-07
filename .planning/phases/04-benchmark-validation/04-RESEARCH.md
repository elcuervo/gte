# Phase 4: Benchmark Validation - Research

**Researched:** 2026-04-07
**Domain:** Ruby benchmarking, fastembed gem comparison, native gem packaging
**Confidence:** HIGH

## Summary

This phase has two distinct deliverables: (1) a benchmark suite proving GTE is faster than the `fastembed` Ruby gem for E5-small at batch sizes 1, 8, and 32, and (2) verification that cross-compiled native gems install and work without a Rust toolchain.

The `fastembed` Ruby gem (v1.1.0) uses the `onnxruntime` Ruby gem (C-backed but with Ruby object marshaling overhead) and the `tokenizers` Ruby gem. GTE calls `ort` and `tokenizers` directly from Rust with zero Ruby-layer overhead for tokenization and inference. This architectural difference should yield a meaningful throughput advantage. The benchmark must use proper warm-up methodology (at least 3 iterations) to ensure JIT/caching effects are stable before timing.

The CI workflow for cross-compilation already exists in `.github/workflows/ci.yml` using `oxidize-rb/actions/cross-gem@v1`. The third success criterion (binary gems install and run without Rust toolchain) requires a CI verification job that installs the built artifact and runs `embed` -- this is a new addition to the existing workflow.

**Primary recommendation:** Use `benchmark-ips` for the throughput comparison (standard Ruby benchmarking gem), write a standalone `bench/benchmark.rb` script, and add a CI job that downloads cross-compiled artifacts and smoke-tests them.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all implementation choices at Claude's discretion (infrastructure phase).

### Claude's Discretion
All implementation choices.

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BENCH-01 | Embedding throughput for E5-small exceeds fastembed gem, measured after warm-up (>=3 warmup iterations) | fastembed uses Ruby onnxruntime+tokenizers gems (marshaling overhead); benchmark-ips with warmup handles methodology |
| BENCH-02 | Benchmark covers batch sizes 1, 8, 32 texts | benchmark-ips supports parameterized runs; script iterates batch sizes |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `benchmark-ips` | latest | Iterations-per-second benchmarking with warmup | De facto Ruby benchmarking gem; handles warmup, statistical reporting |
| `fastembed` | 1.1.0 | Comparison target | The gem GTE must outperform |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `onnxruntime` | ~> 0.9 | Transitive dep of fastembed | Installed automatically |
| `tokenizers` | ~> 0.5 | Transitive dep of fastembed | Installed automatically |

**Installation:**
```bash
gem install benchmark-ips fastembed
```

## Architecture Patterns

### Benchmark Script Structure
```
bench/
  benchmark.rb          # Main benchmark script
  README.md             # How to run, interpret results (optional)
```

### Pattern 1: benchmark-ips with Warmup
**What:** Use `Benchmark.ips` with explicit warmup time ensuring >= 3 iterations warm up before measurement.
**When to use:** All throughput comparisons.
**Example:**
```ruby
require "benchmark/ips"
require "gte"
require "fastembed"

MODEL_PATH = ENV.fetch("MODEL_PATH")
TEXTS_1  = ["query: example text"]
TEXTS_8  = Array.new(8) { |i| "query: sample text number #{i}" }
TEXTS_32 = Array.new(32) { |i| "query: sample text number #{i}" }

gte = GTE::E5.new(model_path: MODEL_PATH)
fe  = Fastembed::TextEmbedding.new(model_name: "intfloat/multilingual-e5-small")

[TEXTS_1, TEXTS_8, TEXTS_32].each do |texts|
  puts "\n--- Batch size: #{texts.size} ---"
  Benchmark.ips do |x|
    x.warmup = 5  # seconds of warmup (ensures >= 3 iterations)
    x.time   = 10 # seconds of measurement

    x.report("gte")       { gte.embed(texts) }
    x.report("fastembed") { fe.embed(texts).to_a }

    x.compare!
  end
end
```

### Pattern 2: CI Smoke Test for Native Gem
**What:** Download cross-compiled gem artifact, install it on a clean runner (no Rust), run a minimal embed call.
**When to use:** Verifying SCAF-06 / success criterion 3.
**Example CI job:**
```yaml
verify:
  name: Verify native gem
  needs: build
  runs-on: ${{ matrix.os }}
  strategy:
    matrix:
      include:
        - os: ubuntu-latest
          platform: x86_64-linux
  steps:
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: "3.4"
    - uses: actions/download-artifact@v4
      with:
        name: bundle-artifact-${{ matrix.platform }}
        path: pkg/
    - name: Install and test
      run: |
        gem install pkg/*.gem
        ruby -e "require 'gte'; puts 'Native gem loaded OK'"
```

Note: A full `embed` smoke test requires model fixtures. The CI verify job can confirm the gem loads and the extension initializes. Full embed verification requires model files which may not be available in CI.

### Anti-Patterns to Avoid
- **Using `Benchmark.measure` or `Time.now` for comparison:** No statistical rigor, no warmup handling. Use benchmark-ips.
- **Forgetting warmup:** ONNX Runtime has session initialization overhead on first inference. Must warm up both GTE and fastembed.
- **Comparing different models:** Both must use E5-small (or equivalent) for fair comparison.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Benchmarking harness | Custom timing loop | `benchmark-ips` | Handles warmup, statistics, comparison formatting |
| Cross-compilation | Custom Cargo cross builds | `oxidize-rb/actions/cross-gem@v1` | Already working in ci.yml |

## Common Pitfalls

### Pitfall 1: Model Mismatch
**What goes wrong:** Comparing GTE with one model vs fastembed with a different model.
**Why it happens:** fastembed defaults to `BAAI/bge-small-en-v1.5`, not E5-small.
**How to avoid:** Explicitly set `model_name: "intfloat/multilingual-e5-small"` for fastembed, use the same ONNX model directory for GTE.
**Warning signs:** Different embedding dimensions between the two.

### Pitfall 2: fastembed Model Download on First Run
**What goes wrong:** First `Fastembed::TextEmbedding.new` downloads the model, adding minutes of network time.
**Why it happens:** fastembed auto-downloads models from HuggingFace Hub.
**How to avoid:** Pre-download the model before benchmarking, or run once to cache it, then benchmark.
**Warning signs:** First benchmark run takes much longer than subsequent ones.

### Pitfall 3: Cold ORT Session
**What goes wrong:** First inference is much slower due to ONNX Runtime session optimization.
**Why it happens:** ORT optimizes the graph on first run.
**How to avoid:** The warmup parameter in benchmark-ips handles this if set to >= 3 seconds (ensuring multiple iterations).
**Warning signs:** Wildly inconsistent early measurements.

### Pitfall 4: arm64-darwin Verification in CI
**What goes wrong:** Cannot verify arm64-darwin gems on GitHub Actions (no macOS ARM runners on free tier).
**Why it happens:** GitHub Actions ubuntu runners are x86_64, macOS runners are available but may cost.
**How to avoid:** Verify x86_64-linux in CI, verify arm64-darwin manually or with `macos-latest` (which is now ARM on GitHub Actions).
**Warning signs:** CI only tests one platform.

## Code Examples

### Minimal Benchmark Script
```ruby
#!/usr/bin/env ruby
# bench/benchmark.rb
# Usage: MODEL_PATH=/path/to/e5-small ruby bench/benchmark.rb

require "benchmark/ips"
require "gte"
require "fastembed"

model_path = ENV.fetch("MODEL_PATH") { abort "Set MODEL_PATH to E5-small ONNX directory" }

gte_model = GTE::E5.new(model_path: model_path)
fe_model  = Fastembed::TextEmbedding.new(model_name: "intfloat/multilingual-e5-small")

# Verify both produce same-dimension embeddings
gte_vec = gte_model.embed("test")
fe_vec  = fe_model.embed(["test"]).to_a.first
puts "GTE dims: #{gte_vec.size}, FastEmbed dims: #{fe_vec.size}"

{ 1 => 1, 8 => 8, 32 => 32 }.each do |label, size|
  texts = Array.new(size) { |i| "query: the quick brown fox #{i}" }

  puts "\n=== Batch size: #{label} ==="
  Benchmark.ips do |x|
    x.warmup = 5
    x.time   = 10

    x.report("gte")       { gte_model.embed(texts) }
    x.report("fastembed") { fe_model.embed(texts).to_a }

    x.compare!
  end
end
```

## Project Constraints (from CLAUDE.md)

- Ruby >= 3.2, Rust edition 2021, ONNX Runtime via `ort` crate
- `rspec` + `rspec-benchmark` for testing
- `oxidize-rb/actions/cross-gem` for CI cross-compilation
- `rake-compiler` for build
- Nix flake for reproducible dev environments
- Models provided as local ONNX files + tokenizer JSON for v1
- `fastembed` gem internal architecture: uses Ruby `onnxruntime` (~> 0.9) + `tokenizers` (~> 0.5) gems -- pure Ruby orchestration over C-backed ONNX runtime

## Open Questions

1. **E5-small model availability for fastembed**
   - What we know: fastembed supports `intfloat/multilingual-e5-small` and auto-downloads it
   - What's unclear: Whether the exact same ONNX model file can be shared between GTE and fastembed (fastembed may quantize or optimize differently)
   - Recommendation: Let fastembed use its own downloaded model; GTE uses its own. Both use E5-small architecture, which is a fair comparison.

2. **macOS ARM CI verification**
   - What we know: GitHub Actions `macos-latest` is now ARM (M1+). Cross-gem builds arm64-darwin gems.
   - What's unclear: Whether oxidize-rb cross-compiled arm64-darwin gems can be tested on `macos-latest` runners.
   - Recommendation: Add macos-latest verify job; if it fails due to runner limitations, document as manual verification step.

## Sources

### Primary (HIGH confidence)
- RubyGems.org fastembed gem page -- confirmed v1.1.0, deps: onnxruntime ~> 0.9, tokenizers ~> 0.5
- Existing `.github/workflows/ci.yml` -- confirmed cross-compilation setup
- Existing `gte.gemspec` -- confirmed dev deps include rspec-benchmark

### Secondary (MEDIUM confidence)
- [fastembed-rb GitHub](https://github.com/khasinski/fastembed-rb) -- API: `Fastembed::TextEmbedding.new(model_name:).embed(texts)`
- benchmark-ips gem -- standard Ruby benchmarking approach (well-known from training data)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - fastembed gem verified on RubyGems, benchmark-ips is well-established
- Architecture: HIGH - straightforward benchmark script + CI job pattern
- Pitfalls: HIGH - common benchmarking methodology concerns, well-understood

**Research date:** 2026-04-07
**Valid until:** 2026-05-07
