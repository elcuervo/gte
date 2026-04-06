# Feature Landscape: Ruby Text Embedding Gem (Rust-backed)

**Domain:** Text embedding library — Ruby gem, Rust extension, ONNX Runtime
**Researched:** 2026-04-06
**Overall confidence:** MEDIUM-HIGH

---

## Table Stakes

Features users expect. Missing = product feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| `embed(text)` single-string call | Every embedding library exposes this | Low | Wraps batch internally |
| `embed([text, ...])` batch call | Batch is the performance primitive | Medium | Core pipeline operation |
| Return `Array<Float>` per input | Universal Ruby interop format | Low | Numo can be additive later |
| Load model from local filesystem path | v1 constraint; all libs support this | Low | tokenizer_path + model_path |
| Tokenization handled internally | Users must not manage tokenization | Medium | HF tokenizers via Rust |
| Deterministic output | Same input produces same embedding | Low | ORT is deterministic by default |
| Meaningful error messages | Bad path, wrong tensor name, truncation | Low | Wrap Rust panics into named Ruby exceptions |
| Thread safety at inference time | Puma/Rails apps are multithreaded | Medium | GVL release required during ORT run |
| Max token length enforcement | All models have context windows | Low | Truncation via HF tokenizers |

---

## Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Throughput faster than fastembed | Core benchmark claim — reason this gem exists | High | Full Rust pipeline, no Ruby in hot path |
| Model-family presets (`GTE::E5`, `GTE::CLIP`, `GTE::Siglip2`) | Correct defaults per model without knowing tensor names | Low | Each preset wraps correct `output_id`, `mode`, etc. |
| `embed_query` / `embed_passage` for E5 | E5 requires task prefixes; hiding this is critical DX | Low | Prefix injection in Rust before tokenization |
| L2-normalized output option | Enables cosine similarity via dot product; expected by `neighbor` gem | Low | Normalize in Rust |
| `configure` block + ENV fallback | Matches nero's pattern; 12-factor app compatible | Low | `GTE_MODEL_PATH` env var |
| Explicit ONNX variant selection | Select `model_quantized.onnx` vs `model.onnx` | Low | Mirrors nero's `default_variant` convention |
| langchainrb duck-type compatibility | `embed_documents` + `embed_query` enables drop-in integration | Low | Method aliasing only |

---

## Anti-Features (v1)

What NOT to build. Each is a scope trap.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Image embeddings (CLIP/Siglip2 vision tower) | Pixel preprocessing pipeline, separate ONNX export | Text-only v1; defer to milestone 2+ |
| Model downloading from HuggingFace Hub | Network, caching, auth, version pinning complexity | Require user-provided local path |
| Reranking | Different task (cross-encoder), different pipeline | Explicitly out of scope |
| Streaming / async / Ractor | Adds concurrency model complexity | Synchronous batch calls cover all use cases |
| Full encoding metadata | Token offsets, attention masks in Ruby — noisy | Return embedding vectors only |
| Auto-chunking of oversized inputs | Silent chunking has surprising behavior | Truncate at max_length; document the limit |
| Built-in similarity search | `neighbor` gem handles this | Return vectors; let user choose storage |
| HTTP server / REST API | Not a library concern | Document Rack integration separately |
| GPU execution provider configuration | Build complexity; unnecessary for v1 benchmark | CPU-only for v1 |

---

## Model-Specific Requirements

### E5 (intfloat/e5-small-v2, intfloat/multilingual-e5-small, etc.)

- **Tokenizer:** WordPiece (BERT-style). `tokenizer.json` from HF export.
- **Token budget:** 512 tokens max. Truncation is correct behavior.
- **ONNX inputs:** `input_ids`, `attention_mask`, `token_type_ids` (the gte-rs `token_types: true` parameter)
- **Output tensor:** `last_hidden_state` shape `[batch, seq_len, hidden_dim]`
- **Extraction mode:** `Token(0)` — CLS token extraction, then mean pooling + L2 normalization
- **Critical prefix requirement (HIGH confidence):** E5 is fine-tuned with task prefixes:
  - `"query: {text}"` — for search queries
  - `"passage: {text}"` — for documents/passages
- **Ruby API:** `embed_query(text)` and `embed_passage(text)` must be first-class methods

### CLIP (openai/clip-vit-base-patch32, etc.)

- **Tokenizer:** BPE (GPT-style), ~49,408 tokens
- **Token budget:** 77 tokens max (hard architectural limit of position embedding table)
- **ONNX inputs:** `input_ids`, `attention_mask`. No `token_type_ids`.
- **Output tensor:** `text_embeds` (not `last_hidden_state`) — pre-pooled, projected embedding
- **Extraction mode:** `Raw` — output is already a sequence embedding
- **Pooling:** None required (ONNX export already pooled)
- **Normalization:** L2 normalize for cosine similarity
- **No prefix requirement**

### Siglip2 (google/siglip2-base-patch16-224, etc.)

- **Tokenizer:** SentencePiece (multilingual). HF ONNX exports include `tokenizer.json`.
- **Token budget:** 64 tokens (SigLIP2 text encoder context length)
- **ONNX inputs:** `input_ids`, `attention_mask`. No `token_type_ids`.
- **Output tensor:** MEDIUM confidence — may be `text_embeds` or `last_hidden_state` depending on export
  - **Action required:** Inspect actual Siglip2 ONNX export to confirm output tensor name and shape
- **Pooling:** Mean pooling or final-token depending on export
- **Normalization:** L2 normalize for retrieval
- **No prefix requirement**

---

## API Ergonomics

### Recommended Ruby API Surface

```ruby
# Model-family entry points
embedder = GTE::E5.new(model_path: "/models/e5-small")
embedder = GTE::CLIP.new(model_path: "/models/clip-vit-b32")
embedder = GTE::Siglip2.new(model_path: "/models/siglip2-base")

# Core embedding
embedder.embed("Hello world")             # => Array<Float>
embedder.embed(["Hello", "World"])        # => Array<Array<Float>>

# E5-specific (required)
embedder.embed_query("What is Ruby?")
embedder.embed_passage("Ruby is a language.")

# langchainrb duck-typing compatibility
embedder.embed_documents(["doc1", "doc2"])  # alias for embed with passage prefix

# Global configuration
GTE.configure do |config|
  config.default_model = "/models/e5-small"
  config.default_variant = "model_quantized"
end

GTE::E5.embed_query("Hello")   # class-level shortcut after configure
```

### Model Directory Convention

```
/models/e5-small/
  tokenizer.json
  onnx/
    model.onnx
    model_quantized.onnx   # optional
```

`GTE::E5.new(model_path: "/models/e5-small")` resolves to:
- tokenizer: `{model_path}/tokenizer.json`
- model: `{model_path}/onnx/{variant}.onnx` where variant defaults to `"model"`

### Output Format

**Return `Array<Float>` by default.** Rationale:
- `neighbor` gem accepts `Array<Float>` directly
- langchainrb expects plain Ruby arrays
- Zero dependencies on Ruby side
- `Array<Array<Float>>` for batch input, single `Array<Float>` for single-string input

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| E5 prefix requirements | HIGH | Documented in intfloat model cards |
| E5 pooling (mean + L2) | HIGH | Standard BERT-family embedding postprocessing |
| CLIP BPE tokenizer, 77-token limit | HIGH | Core CLIP architecture |
| CLIP output tensor `text_embeds` | MEDIUM | Common for HF ONNX exports; must verify |
| Siglip2 pooling strategy | MEDIUM | Architecture knowledge; actual ONNX may differ |
| Siglip2 output tensor name | LOW | Depends on export; must inspect actual file |
| Thread safety / GVL release | HIGH | Standard pattern with magnus |
| neighbor gem Array<Float> compatibility | HIGH | Accepts Ruby arrays directly |

---

## Gaps Requiring Verification

1. **Siglip2 ONNX tensor names** — must inspect an actual export to confirm `output_id`
2. **CLIP position_ids requirement** — varies by ONNX export
3. **fastembed-rb current benchmark numbers** — verify throughput claims on real hardware
4. **langchainrb LLM adapter interface** — verify current method signature
