# Phase 2: Rust Inference Core - Research

**Researched:** 2026-04-06
**Domain:** Rust ONNX inference pipeline — `ort` v2 + HuggingFace `tokenizers` + `ndarray`
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Inference code lives in `ext/gte/src/` as flat modules (e.g., `tokenizer.rs`, `session.rs`, `model_config.rs`) — all inference stays in the single cdylib, no separate library crate
- **D-02:** Adapt gte-rs naming but drop `orp`/`composable` — direct ORT API calls (`SessionBuilder`, `Session::run`) without the pipeline abstraction layer; simpler and more readable for Phase 2
- **D-03:** ModelConfig is a shared trait or struct interface; three concrete types (`E5Config`, `ClipConfig`, `Siglip2Config`) each implementing/holding family-specific defaults (max token length, output extraction strategy)
- **D-04:** `ExtractorMode` is a simple enum `{ E5, Clip, Siglip2 }` with `match` arms for output tensor extraction — no trait objects, explicit and simple
- **D-05:** ONNX model files and `tokenizer.json` live in a git-ignored `tests/fixtures/` directory; tests that require model files are annotated `#[ignore]` so `cargo test` passes without fixtures; CI skips them by default
- **D-06:** Embedding correctness validated by comparing against pre-computed reference vectors stored as inline constants in test code, within float32 tolerance (1e-5)
- **D-07:** Both unit tests (tokenizer logic, no model files needed) AND integration tests (full pipeline, model files required)
- **D-08:** Reference vectors stored as inline array constants in test functions — self-contained, no external fixture files for vectors

### Claude's Discretion

- Exact module file names and internal structure within each module
- How to configure ORT session (CPU provider, thread count, etc.) for tests
- Exact f32 tolerance value (1e-5 is a starting point; adjust if ORT produces slightly different results than Python)
- Whether to expose `ModelConfig` as a public or pub(crate) type in Phase 2 (Phase 3 will need it public)
- L2 normalization placement: in Rust inference core or deferred to Phase 3 (either is fine, but document the choice)

### Deferred Ideas (OUT OF SCOPE)

- GVL release during `session.run` — Phase 3 concern (Ruby threading boundary)
- L2 normalization in the Ruby API layer — could live here or in Phase 3; defer decision to planning
- Model downloading / management — out of scope for v1 (user provides paths)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RUST-01 | Rust pipeline tokenizes a batch of strings using HuggingFace `tokenizers` crate loaded from a local `tokenizer.json` file | Confirmed: `tokenizers::Tokenizer::from_file` + `encode_batch` API verified in gte-rs source |
| RUST-02 | Rust pipeline runs an ONNX model session via `ort` v2 with correct input tensors (`input_ids`, `attention_mask`, and optional `token_type_ids`/`position_ids`) | Confirmed: `Session::builder()?.commit_from_file(path)?` + `Value::from_array(ndarray)` pattern verified |
| RUST-03 | Rust pipeline extracts embeddings from output tensor using configurable extraction mode (CLS token or Raw) | Confirmed: `try_extract_tensor::<f32>()` + slice `s![.., 0, ..]` for CLS or `into_dimensionality::<Ix2>()` for Raw |
| RUST-04 | Rust pipeline is validated against real ONNX model files via Rust integration tests before Ruby bindings are added | Pattern: `#[ignore]` integration tests in `ext/gte/tests/` with `tests/fixtures/` git-ignored |
| RUST-05 | Long inputs are truncated at model max token length (512 for E5, 77 for CLIP, 64 for Siglip2) without error | Confirmed: `TruncationParams { max_length }` + `tokenizer.with_truncation(Some(params))` |
</phase_requirements>

---

## Summary

Phase 2 builds the complete Rust inference pipeline: tokenize → ORT session → embedding extraction. All three pieces have confirmed working API patterns in the `impl/gte-rs/` reference implementation that can be adapted directly. The key constraint (D-02) is to drop the `orp`/`composable` pipeline abstraction and use direct ORT v2 API calls instead, which simplifies the code substantially.

The `tokenizers` crate API is straightforward: load from file, configure truncation and batch-longest padding, call `encode_batch`, then read `get_ids()` and `get_attention_mask()` from each encoding into `ndarray::Array2<i64>` rows. The ORT v2 session API uses `Session::builder()?.commit_from_file(path)?` and `session.run(inputs)` where inputs are a `HashMap<&str, Value>`. Output extraction uses `try_extract_tensor::<f32>()` on the named output, then slicing for CLS-token vs. raw embedding mode.

The model family differences are entirely captured in `ModelConfig`: max token length, output tensor name, extraction mode (`Token(0)` = CLS vs `Raw`), and whether `token_type_ids` are needed. The `ExtractorMode` enum (D-04) is a direct adaptation of gte-rs's `ExtractorMode { Raw, Token(usize) }`. The three families differ as: E5 = CLS token from `last_hidden_state` with `token_type_ids`, CLIP = Raw from `text_embeds` without type IDs, Siglip2 = output tensor TBD (LOW confidence — must inspect model).

**Primary recommendation:** Adapt gte-rs source files directly into `ext/gte/src/` flat modules, replacing `composable`/`orp` with explicit function calls. Unit tests cover tokenizer logic (no fixtures needed); integration tests with `#[ignore]` cover the full pipeline with real model files.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `ort` | `=2.0.0-rc.9` (pinned) | ONNX Runtime — `Session::builder`, `session.run`, tensor I/O | Pinned in gte-rs; only version with confirmed compatible API |
| `tokenizers` | `0.21.0` | HuggingFace tokenizers — `from_file`, `encode_batch`, padding/truncation | Pinned in gte-rs; API confirmed working |
| `ndarray` | `0.16.0` | N-dimensional arrays — `Array2`, `push_row`, slice operations | Pinned in gte-rs; required for ORT tensor construction |
| `half` | `2` | F16/F32 conversion for models with FP16 output | Pinned in gte-rs; needed if model outputs FP16 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `magnus` | `0.8` | Ruby FFI bindings (already in Cargo.toml) | Phase 3 — not used in Phase 2 inference code |
| `rb-sys` | `0.9` | Ruby extension bridge (already in Cargo.toml) | Phase 3 — not used in Phase 2 inference code |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct `Session::run` | `orp` pipeline abstraction | `orp` adds composable complexity; D-02 explicitly requires direct calls |
| Inline `Result<Box<dyn Error>>` | Custom error type | Box<dyn Error> is sufficient for Phase 2; Phase 3 converts to `GTE::Error` |

**Installation (additions to `ext/gte/Cargo.toml`):**
```toml
[dependencies]
ort = { version = "=2.0.0-rc.9", features = ["ndarray"] }
tokenizers = "0.21.0"
ndarray = "0.16.0"
half = "2"
```

Note: `ort` requires the `ndarray` feature flag to enable `Value::from_array(ndarray::Array)`.

---

## Architecture Patterns

### Recommended Module Structure

```
ext/gte/src/
├── lib.rs           # Magnus init + GTE::Error + panic hook (existing, Phase 1)
├── tokenizer.rs     # Tokenizer struct: from_file, encode_batch → Tokenized
├── session.rs       # Session wrapper: builder, run → raw SessionOutputs
├── model_config.rs  # ModelConfig trait/struct, E5Config, ClipConfig, Siglip2Config
├── embedder.rs      # Embedder: holds Tokenizer + Session + ModelConfig, run() → Array2<f32>
└── error.rs         # Type alias: pub(crate) type Result<T> = core::result::Result<T, GteError>

ext/gte/tests/
├── tokenizer_test.rs     # Unit: tokenizer without model files (#[cfg(test)])
└── inference_test.rs     # Integration: full pipeline, requires fixtures, #[ignore]

ext/gte/tests/fixtures/   # git-ignored: tokenizer.json + model.onnx per model family
```

### Pattern 1: Tokenizer Module

**What:** Wrap `tokenizers::Tokenizer` to produce `ndarray::Array2<i64>` tensors from a batch of strings.
**When to use:** Called by `Embedder::embed()` before ORT session run.

```rust
// Source: impl/gte-rs/src/tokenizer/mod.rs (direct adaptation)
use std::path::Path;

pub struct Tokenizer {
    tokenizer: tokenizers::Tokenizer,
    with_type_ids: bool,
}

pub struct Tokenized {
    pub input_ids: ndarray::Array2<i64>,
    pub attn_masks: ndarray::Array2<i64>,
    pub type_ids: Option<ndarray::Array2<i64>>,
}

impl Tokenizer {
    pub fn new<P: AsRef<Path>>(
        tokenizer_path: P,
        max_length: usize,
        with_type_ids: bool,
    ) -> crate::Result<Self> {
        let mut tokenizer = tokenizers::Tokenizer::from_file(tokenizer_path)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        let mut truncation = tokenizers::TruncationParams::default();
        truncation.max_length = max_length;
        tokenizer.with_truncation(Some(truncation))
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;

        let mut padding = tokenizers::PaddingParams::default();
        padding.strategy = tokenizers::PaddingStrategy::BatchLongest;
        tokenizer.with_padding(Some(padding));

        Ok(Self { tokenizer, with_type_ids })
    }

    pub fn tokenize(&self, texts: Vec<String>) -> crate::Result<Tokenized> {
        let encodings = self.tokenizer.encode_batch(texts, true)
            .map_err(|e| GteError::Tokenizer(e.to_string()))?;
        let max_tokens = encodings.first().map(|e| e.len()).unwrap_or(0);
        let mut input_ids = ndarray::Array2::zeros((0, max_tokens));
        let mut attn_masks = ndarray::Array2::zeros((0, max_tokens));
        let mut type_ids = self.with_type_ids.then(|| ndarray::Array2::zeros((0, max_tokens)));
        for enc in &encodings {
            let ids: Vec<i64> = enc.get_ids().iter().map(|&x| x as i64).collect();
            let masks: Vec<i64> = enc.get_attention_mask().iter().map(|&x| x as i64).collect();
            input_ids.push_row(ndarray::ArrayView::from(&ids)).unwrap();
            attn_masks.push_row(ndarray::ArrayView::from(&masks)).unwrap();
            if let Some(ref mut t) = type_ids {
                let tids: Vec<i64> = enc.get_type_ids().iter().map(|&x| x as i64).collect();
                t.push_row(ndarray::ArrayView::from(&tids)).unwrap();
            }
        }
        Ok(Tokenized { input_ids, attn_masks, type_ids })
    }
}
```

### Pattern 2: ORT Session Creation and Run

**What:** Direct `Session::builder()` + `session.run()` without `orp` abstraction.
**When to use:** Called by `Embedder::embed()` with tensors from `Tokenizer::tokenize()`.

```rust
// Source: ort docs 2.0.0-rc.9, adapted from gte-rs pattern
use ort::session::Session;
use ort::value::Value;
use std::collections::HashMap;

pub fn build_session<P: AsRef<std::path::Path>>(
    model_path: P,
) -> crate::Result<Session> {
    let session = Session::builder()?
        .commit_from_file(model_path)?;
    Ok(session)
}

pub fn run_session(
    session: &Session,
    tokenized: &Tokenized,
    config: &ModelConfig,
) -> crate::Result<ort::session::SessionOutputs> {
    let mut inputs: HashMap<&str, Value<_>> = HashMap::new();
    inputs.insert("input_ids", Value::from_array(tokenized.input_ids.view())?);
    inputs.insert("attention_mask", Value::from_array(tokenized.attn_masks.view())?);
    if let Some(ref t) = tokenized.type_ids {
        inputs.insert("token_type_ids", Value::from_array(t.view())?);
    }
    let outputs = session.run(inputs)?;
    Ok(outputs)
}
```

**Critical note on lifetime:** `SessionOutputs` borrows from `Session`. The `Embedder` struct must hold both `Session` and handle the borrow correctly — extract embeddings before returning (don't return `SessionOutputs` from a method that drops `Session`).

### Pattern 3: ExtractorMode and Embedding Extraction

**What:** Pull the correct output tensor by name, apply CLS-token slice or raw 2D extraction.
**When to use:** After `session.run()` returns `SessionOutputs`.

```rust
// Source: impl/gte-rs/src/embed/output.rs (direct adaptation)
#[derive(Debug, Clone, Copy)]
pub enum ExtractorMode {
    /// Output tensor is shape [batch, seq, dim] — take token at `index` (usually 0 = CLS)
    Token(usize),
    /// Output tensor is shape [batch, dim] — use as-is
    Raw,
}

pub fn extract_embeddings(
    outputs: &ort::session::SessionOutputs,
    output_tensor_name: &str,
    mode: ExtractorMode,
) -> crate::Result<ndarray::Array2<f32>> {
    let tensor = outputs
        .get(output_tensor_name)
        .ok_or_else(|| GteError::Inference(format!("tensor '{}' not in outputs", output_tensor_name)))?;

    let array = tensor.try_extract_tensor::<f32>()?;

    match mode {
        ExtractorMode::Raw => {
            // shape [batch, dim]
            let arr2 = array.into_dimensionality::<ndarray::Ix2>()?;
            Ok(arr2.into_owned())
        }
        ExtractorMode::Token(idx) => {
            // shape [batch, seq, dim] — slice to [batch, dim]
            let embeddings = array.slice(ndarray::s![.., idx, ..]);
            Ok(embeddings.into_owned())
        }
    }
}
```

### Pattern 4: ModelConfig

**What:** Per-family configuration struct holding all inference parameters.
**When to use:** Passed to `Embedder::new()` and used during `tokenize` and `extract`.

```rust
// Source: impl/gte-rs/src/params/mod.rs (simplified, dropping builder pattern)
pub struct ModelConfig {
    pub max_length: usize,
    pub output_tensor: &'static str,
    pub mode: ExtractorMode,
    pub with_type_ids: bool,
}

impl ModelConfig {
    pub fn e5() -> Self {
        Self {
            max_length: 512,
            output_tensor: "last_hidden_state",
            mode: ExtractorMode::Token(0),  // CLS token
            with_type_ids: true,
        }
    }

    pub fn clip() -> Self {
        Self {
            max_length: 77,
            output_tensor: "text_embeds",
            mode: ExtractorMode::Raw,
            with_type_ids: false,
        }
    }

    pub fn siglip2() -> Self {
        Self {
            max_length: 64,
            output_tensor: "???",  // LOW confidence — must inspect model
            mode: ExtractorMode::Raw,  // likely Raw — verify
            with_type_ids: false,
        }
    }
}
```

### Pattern 5: Integration Test Structure

**What:** `#[ignore]`-annotated tests in `ext/gte/tests/` that require fixture files.
**When to use:** For RUST-02, RUST-03, RUST-04.

```rust
// ext/gte/tests/inference_test.rs
#[cfg(test)]
mod e5_tests {
    use super::*;

    // Run with: cargo test -- --ignored
    #[test]
    #[ignore = "requires tests/fixtures/e5/tokenizer.json and model.onnx"]
    fn test_e5_embedding_correctness() {
        const TOKENIZER: &str = "tests/fixtures/e5/tokenizer.json";
        const MODEL: &str = "tests/fixtures/e5/model.onnx";
        const EPSILON: f32 = 1e-5;

        // Reference vectors from Python sentence-transformers
        const EXPECTED: [f32; 384] = [ /* ... pre-computed ... */ ];

        let config = ModelConfig::e5();
        let embedder = Embedder::new(TOKENIZER, MODEL, config).unwrap();
        let embeddings = embedder.embed(vec!["Hello, world!".to_string()]).unwrap();

        let actual = embeddings.row(0);
        for (a, e) in actual.iter().zip(EXPECTED.iter()) {
            assert!((a - e).abs() < EPSILON, "embedding mismatch: {} vs {}", a, e);
        }
    }
}
```

### Pattern 6: Unit Test (No Fixtures Required)

**What:** Test tokenizer output shape and truncation without any model files.
**When to use:** Fast feedback during development, runs in CI without fixtures.

```rust
// ext/gte/tests/tokenizer_test.rs OR inline in ext/gte/src/tokenizer.rs
#[cfg(test)]
mod tests {
    #[test]
    fn test_tokenizer_batch_padding() {
        // requires tokenizer.json — use a tiny one from fixtures or skip
        // OR test the Array2 shape arithmetic without a real tokenizer
    }

    #[test]
    fn test_truncation_respected() {
        // tokenize a 1000-token input, assert output has exactly max_length tokens
    }
}
```

### Anti-Patterns to Avoid

- **Returning `SessionOutputs` from `Embedder::embed()`**: `SessionOutputs<'s, 's>` borrows from the `Session` with lifetime `'s`. Extract the `Array2<f32>` inside `embed()` before returning — do not return the raw outputs.
- **Using `orp` or `composable` crates**: D-02 locks against these. Direct function calls only.
- **Calling `Session::new()` (v1 API)**: Use `Session::builder()?.commit_from_file(path)?`. The v1 `SessionBuilder::new()` signature does not exist in ort v2.
- **Separate library crate for inference code**: D-01 locks against this. All modules stay inside the `cdylib` at `ext/gte/src/`.
- **Using `.unwrap()` in non-test code**: Use `?` throughout the inference path. Phase 3 converts `Result` to `GTE::Error`.
- **Committing model files**: `tests/fixtures/` must be in `.gitignore`. Models are user-provided binary artifacts.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tokenization (BPE/WordPiece) | Custom tokenizer | `tokenizers = "0.21.0"` | BPE merges, special token insertion, attention mask, and padding are extremely complex to get right |
| ONNX operator execution | Custom ONNX runner | `ort = "=2.0.0-rc.9"` | ONNX graph execution, memory management, and hardware dispatch are infeasible to replicate |
| Batch padding to longest | Manual vector padding | `PaddingStrategy::BatchLongest` | Tokenizers handles variable-length batch collation correctly |
| Truncation at max tokens | Manual token slicing | `TruncationParams::max_length` | Must truncate at subword boundaries, not character boundaries |
| F16 → F32 conversion | Manual bit cast | `half::f16::to_f32()` | IEEE 754 half-precision has edge cases (NaN, Inf, subnormal) |

**Key insight:** The tokenizer and ONNX runtime together account for >95% of inference complexity. All work in Phase 2 is wiring these existing libraries together correctly.

---

## Runtime State Inventory

Step 2.5 SKIPPED — Phase 2 is a greenfield code addition (new Rust modules + tests), not a rename/refactor/migration phase. No existing runtime state is modified.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Rust/Cargo | All Rust compilation | Homebrew | cargo 1.93.0 | None — required |
| Nix | Reproducible dev shell with ORT | System | 2.31.2 | Manual ORT install (see below) |
| ONNX Runtime (system lib) | ORT_STRATEGY=system in flake | Via Nix devShell | nixpkgs-unstable | Must use `nix develop` |
| Ruby 3.4 | rake compile (Phase 3) | Via Nix devShell | 3.4 in Nix | Phase 2 needs cargo only |
| `tests/fixtures/` model files | Integration tests (RUST-04) | Not present | N/A | Tests annotated `#[ignore]` |

**Missing dependencies with no fallback:**
- ONNX Runtime system library: must enter `nix develop` before running `cargo test` on integration tests. The `ORT_STRATEGY=system` env var set in `flake.nix` shellHook tells ort where to find the lib. Outside the Nix shell, `cargo test` on the tokenizer unit tests will still work (no ORT link needed until ORT is added as a dep).

**Missing dependencies with fallback:**
- Model fixture files: integration tests gated behind `#[ignore]`. `cargo test` (without `-- --ignored`) passes with zero fixtures.

**Important:** `ORT_LIB_LOCATION` is set to `${pkgs.onnxruntime}` (the store path) in the Nix shellHook. Cargo/ort use this to find the `.dylib`/`.so` at link time. This is already wired in `flake.nix` — no additional configuration needed for Phase 2.

---

## Common Pitfalls

### Pitfall 1: SessionOutputs Lifetime
**What goes wrong:** `SessionOutputs<'s, 's>` borrows from the `Session` with lifetime `'s`. Trying to return `SessionOutputs` from a function that also owns `Session` causes a lifetime error, or storing `SessionOutputs` in a struct alongside `Session` requires self-referential patterns.
**Why it happens:** ORT's zero-copy output design borrows output memory from the session's allocator.
**How to avoid:** Always extract the embedding `Array2<f32>` from `SessionOutputs` before returning from `embed()`. The pattern is: run → extract → drop outputs → return owned array.
**Warning signs:** Compiler error "borrowed value does not live long enough" or "cannot return value referencing local variable".

### Pitfall 2: ORT Feature Flag for ndarray
**What goes wrong:** `Value::from_array(ndarray_array)` fails to compile with "method not found" or "trait bound not satisfied".
**Why it happens:** The `ndarray` integration in `ort` is behind a feature flag.
**How to avoid:** Add `ort = { version = "=2.0.0-rc.9", features = ["ndarray"] }` in Cargo.toml.
**Warning signs:** Compile error on `Value::from_array` call with ndarray input.

### Pitfall 3: SessionInputs HashMap Type Mismatch
**What goes wrong:** Building a `HashMap<&str, Value<TensorValueType<i64>>>` works for `input_ids`/`attention_mask`, but mixing i64 and f32 tensors in the same HashMap fails.
**Why it happens:** `ort::value::Value` is generic over its tensor type; a HashMap requires a single concrete type.
**How to avoid:** All input tensors for transformer models are `i64` (token IDs, masks). Keep inputs as `HashMap<&str, Value<TensorValueType<i64>>>`. Use `ort::inputs![]` macro if mixing types becomes necessary.
**Warning signs:** Type error when trying to insert a differently-typed Value into the map.

### Pitfall 4: Tokenizer `with_truncation` Error Handling
**What goes wrong:** `tokenizer.with_truncation(Some(params))` returns a `Result` that is easy to miss when chaining builder-style calls.
**Why it happens:** Truncation configuration can fail (e.g., conflicting params), unlike `with_padding` which is infallible.
**How to avoid:** Always propagate the `?` or `map_err` from `with_truncation`. See gte-rs `tokenizer/mod.rs` line 27.
**Warning signs:** Silent truncation failure; tokens are not actually truncated.

### Pitfall 5: ExtractorMode Token Index vs. Array Shape
**What goes wrong:** For `Token(0)` (CLS), slicing `array.slice(s![.., 0, ..])` requires the output tensor to be rank-3 `[batch, seq, dim]`. If the model outputs rank-2 (already pooled), this panics.
**Why it happens:** Different model architectures pool differently. E5 outputs `last_hidden_state` at rank-3; multilingual models may output rank-2.
**How to avoid:** Verify output tensor rank before deploying `Token(0)` mode. For E5, `last_hidden_state` is confirmed rank-3.
**Warning signs:** "index out of bounds" or ndarray dimensionality error at slice time.

### Pitfall 6: Siglip2 Output Tensor Name is Unknown
**What goes wrong:** Writing `Siglip2Config` with a hardcoded output tensor name without inspecting the actual ONNX file — the integration test silently returns an error "tensor '???' not found".
**Why it happens:** Siglip2 ONNX export varies by tool and version. This is a known LOW-confidence item in STATE.md.
**How to avoid:** Inspect the actual Siglip2 ONNX model with `python -c "import onnx; m=onnx.load('model.onnx'); print([o.name for o in m.graph.output])"` before writing the config. Defer Siglip2Config output tensor name to test time.
**Warning signs:** Integration test error: "tensor not found in model output".

### Pitfall 7: `cargo test` Tries to Link ORT Outside Nix Shell
**What goes wrong:** Running `cargo test` outside `nix develop` fails to link because `ORT_STRATEGY=system` requires the Nix-provided ORT library.
**Why it happens:** `ORT_STRATEGY=system` tells ort to link against the system-installed library (at `ORT_LIB_LOCATION`), not download one. Outside the Nix shell, neither env var is set.
**How to avoid:** Always run `cargo test` and `cargo build` from within `nix develop`. Document this in test setup instructions.
**Warning signs:** Link error mentioning `libonnxruntime` not found.

---

## Code Examples

Verified patterns from official sources and confirmed gte-rs reference:

### Cargo.toml additions (ort feature flag required)
```toml
# Source: impl/gte-rs/Cargo.toml + ort docs verification
[dependencies]
ort = { version = "=2.0.0-rc.9", features = ["ndarray"] }
tokenizers = "0.21.0"
ndarray = "0.16.0"
half = "2"
```

### Tokenizer construction with truncation
```rust
// Source: impl/gte-rs/src/tokenizer/mod.rs lines 22-35
let mut tokenizer = tokenizers::Tokenizer::from_file(path)?;

let mut truncation = tokenizers::TruncationParams::default();
truncation.max_length = 512;  // E5
tokenizer.with_truncation(Some(truncation))?;  // note: returns Result

let mut padding = tokenizers::PaddingParams::default();
padding.strategy = tokenizers::PaddingStrategy::BatchLongest;
tokenizer.with_padding(Some(padding));  // infallible
```

### Batch encoding to ndarray rows
```rust
// Source: impl/gte-rs/src/tokenizer/mod.rs lines 38-56
let encodings = tokenizer.encode_batch(texts, true)?;  // true = add special tokens
let max_tokens = encodings.first().map(|e| e.len()).unwrap_or(0);
let mut input_ids = ndarray::Array2::<i64>::zeros((0, max_tokens));
for enc in &encodings {
    let ids: Vec<i64> = enc.get_ids().iter().map(|&x| x as i64).collect();
    input_ids.push_row(ndarray::ArrayView::from(&ids)).unwrap();
}
```

### ORT session creation (v2 API)
```rust
// Source: ort 2.0.0-rc.9 docs, verified
use ort::session::Session;

let session = Session::builder()?
    .commit_from_file("path/to/model.onnx")?;
```

### ORT session run with HashMap inputs
```rust
// Source: impl/gte-rs/src/commons/input/tensors.rs adapted
use std::collections::HashMap;
use ort::value::Value;

let mut inputs: HashMap<&str, Value<ort::value::TensorValueType<i64>>> = HashMap::new();
inputs.insert("input_ids", Value::from_array(input_ids.view())?);
inputs.insert("attention_mask", Value::from_array(attn_masks.view())?);
// optional:
inputs.insert("token_type_ids", Value::from_array(type_ids.view())?);

let outputs = session.run(inputs)?;
```

### Output extraction (CLS token mode)
```rust
// Source: impl/gte-rs/src/embed/output.rs lines 98-102
let tensor = outputs["last_hidden_state"].try_extract_tensor::<f32>()?;
// tensor shape: [batch, seq, dim]
let cls = tensor.slice(ndarray::s![.., 0, ..]);  // shape: [batch, dim]
let embeddings: ndarray::Array2<f32> = cls.into_owned();
```

### Output extraction (Raw mode)
```rust
// Source: impl/gte-rs/src/embed/output.rs lines 93-97
let tensor = outputs["text_embeds"].try_extract_tensor::<f32>()?;
// tensor shape: [batch, dim]
let embeddings = tensor.into_dimensionality::<ndarray::Ix2>()?.into_owned();
```

### Float comparison utility (adapted from gte-rs util/test.rs)
```rust
// Source: impl/gte-rs/src/util/test.rs
fn is_close(a: f32, b: f32, epsilon: f32) -> bool {
    (a - b).abs() <= epsilon
}

fn embeddings_match(actual: &[f32], expected: &[f32], epsilon: f32) -> bool {
    actual.len() == expected.len()
        && actual.iter().zip(expected).all(|(a, e)| is_close(*a, *e, epsilon))
}
```

### Integration test skeleton
```rust
// ext/gte/tests/inference_test.rs
#[test]
#[ignore = "requires tests/fixtures/e5/tokenizer.json and tests/fixtures/e5/model.onnx"]
fn test_e5_single_embedding_correctness() {
    const TOKENIZER: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5/tokenizer.json");
    const MODEL: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/e5/model.onnx");

    // Reference: run once in Python with sentence-transformers, capture first N dims
    const EXPECTED_FIRST_8: [f32; 8] = [0.0213, -0.0541, 0.0812, /* ... */];
    const EPSILON: f32 = 1e-4;  // wider tolerance for cross-runtime comparison

    let config = ModelConfig::e5();
    let embedder = Embedder::new(TOKENIZER, MODEL, config).expect("embedder init");
    let result = embedder.embed(vec!["test sentence".to_string()]).expect("embed");
    let row = result.row(0);

    for (i, (a, e)) in row.iter().zip(&EXPECTED_FIRST_8).enumerate() {
        assert!(
            (a - e).abs() < EPSILON,
            "dim {}: actual={} expected={} diff={}",
            i, a, e, (a - e).abs()
        );
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `SessionBuilder::new()` (ort v1) | `Session::builder()` (ort v2) | v2 RC series | All ort v1 examples online use wrong API |
| `ort::inputs![]` for all input types | `HashMap<&str, Value<T>>` for typed inputs | v2 design | More explicit but requires matching the concrete type T |
| ORT_STRATEGY=download | ORT_STRATEGY=system in Nix | Project decision | Reproducible; eliminates download-at-build-time surprises |

**Deprecated/outdated:**
- ort v1 `SessionBuilder::new()`: Does not exist in v2. All StackOverflow answers and blog posts predating 2024 use v1 API.
- `rutie` crate: Unmaintained. The Ruby FFI layer uses `magnus` (Phase 3 concern).

---

## Open Questions

1. **Siglip2 output tensor name**
   - What we know: Siglip2 is a vision-language model; text embeddings are extracted from a named output tensor. CLIP uses `"text_embeds"`. Siglip2 likely differs.
   - What's unclear: The exact output name depends on how the ONNX was exported. Cannot be confirmed without inspecting the actual model file.
   - Recommendation: Write `Siglip2Config` with a `TODO` placeholder for `output_tensor`. The plan should include a task "inspect Siglip2 ONNX and set output tensor name" that must run before the Siglip2 integration test can be written.

2. **Float32 tolerance for ORT vs. Python sentence-transformers**
   - What we know: D-06 specifies 1e-5 as a starting point. gte-rs examples use 1e-6 for cross-sentence distances.
   - What's unclear: ORT on CPU (especially on aarch64-darwin) may produce slightly different results from Python/PyTorch due to FP32 operation ordering. The actual tolerance may need to be 1e-4.
   - Recommendation: Pre-compute reference vectors in Python and verify tolerance empirically when running the first integration test. Allow the plan to specify 1e-4 as the starting tolerance, tightening to 1e-5 if results agree.

3. **Position IDs for any of the three model families**
   - What we know: E5 uses `token_type_ids: true`, CLIP and Siglip2 likely `false`. gte-rs Tokenizer also supports `with_position_ids` for models needing explicit position tensors.
   - What's unclear: Whether any v1 target models require `position_ids` in addition to `token_type_ids`.
   - Recommendation: Implement `position_ids` support in `ModelConfig` (copy from gte-rs pattern) but leave it `false` for all three Phase 2 configs until a model requires it.

---

## Sources

### Primary (HIGH confidence)
- `impl/gte-rs/src/tokenizer/mod.rs` — Complete tokenizer API: `from_file`, `encode_batch`, `TruncationParams`, `PaddingParams::BatchLongest`, `ndarray::Array2` construction via `push_row`
- `impl/gte-rs/src/embed/output.rs` — `ExtractorMode` enum (`Raw`, `Token(usize)`), `try_extract_tensor::<f32>()`, CLS slice pattern `s![.., 0, ..]`, `into_dimensionality::<Ix2>()`
- `impl/gte-rs/src/commons/input/tensors.rs` — `HashMap<&str, Value<TensorValueType<i64>>>` session input pattern, `Value::from_array`
- `impl/gte-rs/src/params/mod.rs` — `Parameters` struct fields: `max_length`, `token_types`, `positions`, `output_id`, `mode`, `precision`
- `impl/gte-rs/src/commons/output/tensors.rs` — `SessionOutputs` wrapping pattern
- `impl/gte-rs/src/util/test.rs` — Float comparison helpers `is_close_to`, `is_close_to_a`
- `impl/gte-rs/Cargo.toml` — Confirmed version pins: `ort = "=2.0.0-rc.9"`, `tokenizers = "0.21.0"`, `ndarray = "0.16.0"`, `half = "2"`
- `ext/gte/src/lib.rs` — Existing skeleton state: `#[magnus::init]`, `GTE::Error`, panic hook in place
- `ext/gte/Cargo.toml` — Current deps: `rb-sys 0.9`, `magnus 0.8` — ort/tokenizers/ndarray/half not yet added
- `flake.nix` — ORT env: `ORT_STRATEGY=system`, `ORT_LIB_LOCATION=${pkgs.onnxruntime}` — already correct
- [ort 2.0.0-rc.9 docs — Session::builder, commit_from_file, session.run](https://docs.rs/ort/2.0.0-rc.9/ort/)
- [ort Value::from_array — ndarray integration, try_extract_tensor](https://docs.rs/ort/2.0.0-rc.9/ort/value/struct.Value.html)

### Secondary (MEDIUM confidence)
- [WebSearch verified] Session::builder API: `.with_optimization_level()`, `.with_intra_threads()`, `.commit_from_file()` — confirmed matches ort v2 docs
- [WebSearch verified] `ort::inputs![]` macro exists as alternative to HashMap for session inputs

### Tertiary (LOW confidence)
- Siglip2 ONNX output tensor name — no authoritative source found; must inspect model
- Exact float32 tolerance for cross-runtime comparison — 1e-4 to 1e-5 range based on community reports; needs empirical validation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all versions confirmed from gte-rs Cargo.toml source code
- Architecture: HIGH — direct adaptation of gte-rs patterns with orp/composable removed per D-02
- ORT v2 session API: HIGH — verified from official docs
- Tokenizer API: HIGH — verified from gte-rs source (directly runnable reference)
- Siglip2 output tensor: LOW — must inspect actual model file
- Float tolerance: MEDIUM — 1e-5 stated in D-06; empirical validation needed

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (ort rc series may advance; pin is locked so no impact)
