#!/usr/bin/env python3
"""Benchmark and reference-vector generator for Python ONNX Runtime parity."""

import argparse
import json
import os
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

BATCH_SIZES = [1, 8, 32, 128]
ITERATIONS = 20
PREFERRED_OUTPUTS = [
    "text_embeds",
    "pooler_output",
    "sentence_embedding",
    "last_hidden_state",
]
REFERENCE_TEXTS = {
    "E5": [
        "query: benchmark validation probe",
        "query: machine learning basics",
        "passage: gradient descent updates model parameters",
    ],
    "CLIP": [
        "a photo of a cat",
        "a picture of a kitten",
        "a blueprint of a skyscraper",
    ],
    "Siglip2": [
        "a photo of a cat",
        "a photo of a dog",
        "a geometric abstract logo",
    ],
}


def latency_stats(fn, iterations=ITERATIONS):
    fn()  # warmup
    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        fn()
        times.append((time.perf_counter() - start) * 1000)
    times.sort()
    n = len(times)
    return {
        "median": times[n // 2],
        "p95": times[int(n * 0.95)],
        "p99": times[int(n * 0.99)],
    }


def normalize_l2(embeddings):
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms[norms == 0] = 1
    return embeddings / norms


def read_max_length(model_dir):
    path = Path(model_dir) / "tokenizer_config.json"
    if path.exists():
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
            value = data.get("model_max_length")
            if isinstance(value, int):
                return min(value, 8192)
    return 512


def resolve_model_path(model_dir):
    candidates = [
        Path(model_dir) / "onnx" / "text_model.onnx",
        Path(model_dir) / "text_model.onnx",
        Path(model_dir) / "onnx" / "model.onnx",
        Path(model_dir) / "model.onnx",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    raise FileNotFoundError(f"no ONNX model found in {model_dir}")


def output_name_matches(name, preferred):
    lower = name.lower()
    return lower == preferred or lower.endswith(f"/{preferred}")


def select_output_name(session):
    output_names = [out.name for out in session.get_outputs()]
    for preferred in PREFERRED_OUTPUTS:
        for name in output_names:
            if output_name_matches(name, preferred):
                return name
    if not output_names:
        raise RuntimeError("model has no outputs")
    return output_names[0]


def infer_mode(output_shape):
    rank = len(output_shape)
    if rank == 2:
        return "raw"
    if rank == 3:
        return "mean_pool"
    raise RuntimeError(f"unsupported output rank {rank}; expected 2 or 3")


def inspect_session(model_dir):
    model_path = resolve_model_path(model_dir)
    session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
    input_names = [i.name for i in session.get_inputs()]
    unsupported = [
        n for n in input_names if n not in ("input_ids", "attention_mask", "token_type_ids")
    ]
    if unsupported:
        hint = ""
        if "pixel_values" in unsupported:
            hint = " (multimodal graph detected; provide text_model.onnx)"
        raise RuntimeError(f"unsupported inputs for text embedding: {unsupported}{hint}")

    output_name = select_output_name(session)
    output_shape = None
    for out in session.get_outputs():
        if out.name == output_name:
            output_shape = out.shape
            break
    if output_shape is None:
        raise RuntimeError(f"output '{output_name}' not found")

    mode = infer_mode(output_shape)
    with_attention_mask = "attention_mask" in input_names
    if mode == "mean_pool" and not with_attention_mask:
        raise RuntimeError("mean pooling requires attention_mask input")

    return {
        "session": session,
        "output_name": output_name,
        "mode": mode,
        "with_attention_mask": with_attention_mask,
        "with_type_ids": "token_type_ids" in input_names,
        "max_length": read_max_length(model_dir),
    }


def load_tokenizer(model_dir):
    tokenizer = Tokenizer.from_file(str(Path(model_dir) / "tokenizer.json"))
    # Match Rust behavior: override tokenizer.json static padding/truncation
    # with dynamic BatchLongest + explicit max_length handling in build_inputs.
    tokenizer.no_padding()
    tokenizer.no_truncation()
    return tokenizer


def build_inputs(tokenizer, texts, max_length, with_attention_mask, with_type_ids):
    encoded = tokenizer.encode_batch(texts)
    max_len = min(max(len(e.ids) for e in encoded), max_length) if encoded else 0

    input_ids = np.array(
        [e.ids[:max_len] + [0] * max(0, max_len - len(e.ids)) for e in encoded],
        dtype=np.int64,
    )
    feeds = {"input_ids": input_ids}

    if with_attention_mask:
        attn = np.array(
            [
                e.attention_mask[:max_len]
                + [0] * max(0, max_len - len(e.attention_mask))
                for e in encoded
            ],
            dtype=np.int64,
        )
        feeds["attention_mask"] = attn

    if with_type_ids:
        type_ids = np.array(
            [e.type_ids[:max_len] + [0] * max(0, max_len - len(e.type_ids)) for e in encoded],
            dtype=np.int64,
        )
        feeds["token_type_ids"] = type_ids

    return feeds


def embed_batch(model_dir, texts):
    tokenizer = load_tokenizer(model_dir)
    config = inspect_session(model_dir)
    feeds = build_inputs(
        tokenizer,
        texts,
        config["max_length"],
        config["with_attention_mask"],
        config["with_type_ids"],
    )
    out = config["session"].run([config["output_name"]], feeds)[0]

    if config["mode"] == "mean_pool":
        mask = feeds["attention_mask"].astype(np.float32)
        mask_expanded = np.expand_dims(mask, -1)
        summed = np.sum(out * mask_expanded, axis=1)
        counts = np.sum(mask, axis=1, keepdims=True)
        counts[counts == 0] = 1
        embeddings = summed / counts
    else:
        embeddings = out

    return normalize_l2(embeddings)


def run_benchmark(name, model_dir):
    print(f"\n{name} — Python ORT Latency")
    print("-" * 60)
    config = inspect_session(model_dir)
    tokenizer = load_tokenizer(model_dir)

    for size in BATCH_SIZES:
        texts = [f"This is benchmark text number {i} for embedding" for i in range(size)]

        def run():
            feeds = build_inputs(
                tokenizer,
                texts,
                config["max_length"],
                config["with_attention_mask"],
                config["with_type_ids"],
            )
            out = config["session"].run([config["output_name"]], feeds)[0]
            if config["mode"] == "mean_pool":
                mask = feeds["attention_mask"].astype(np.float32)
                summed = np.sum(out * np.expand_dims(mask, -1), axis=1)
                counts = np.sum(mask, axis=1, keepdims=True)
                counts[counts == 0] = 1
                normalize_l2(summed / counts)
            else:
                normalize_l2(out)

        stats = latency_stats(run)
        per_item = stats["median"] / size
        print(
            f"  batch={size:3d}  median={stats['median']:7.2f}ms"
            f"  p95={stats['p95']:7.2f}ms  p99={stats['p99']:7.2f}ms"
            f"  per_item={per_item:6.2f}ms"
        )

    probe = REFERENCE_TEXTS[name][0]
    emb = embed_batch(model_dir, [probe])[0]
    print(f"\n  {name} first 5 values: {emb[:5].round(6).tolist()}")


def emit_reference(path, model_dirs):
    refs = {}
    for name, model_dir in model_dirs.items():
        if not model_dir:
            continue
        refs[name.lower()] = {
            "texts": REFERENCE_TEXTS[name],
            "embeddings": embed_batch(model_dir, REFERENCE_TEXTS[name]).tolist(),
        }

    if not refs:
        raise RuntimeError("no model directories provided for reference generation")

    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(refs, f)
    print(f"wrote reference vectors: {output_path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--emit-reference",
        metavar="PATH",
        help="write deterministic reference embeddings JSON and exit",
    )
    args = parser.parse_args()

    model_dirs = {
        "E5": os.environ.get("GTE_MODEL_DIR"),
        "CLIP": os.environ.get("GTE_CLIP_DIR"),
        "Siglip2": os.environ.get("GTE_SIGLIP2_DIR"),
    }

    if args.emit_reference:
        emit_reference(args.emit_reference, model_dirs)
        return

    print("Python ORT Benchmark")
    print("=" * 60)

    for name in ["E5", "CLIP", "Siglip2"]:
        model_dir = model_dirs[name]
        if model_dir:
            run_benchmark(name, model_dir)

    print("\nDone.")


if __name__ == "__main__":
    main()
