#!/usr/bin/env python3
import argparse
import json
import math
import os
import sys


MODEL_CANDIDATES = [
    os.path.join("onnx", "text_model.onnx"),
    "text_model.onnx",
    os.path.join("onnx", "model.onnx"),
    "model.onnx",
]
OUTPUT_PREFERENCES = [
    "text_embeds",
    "pooler_output",
    "sentence_embedding",
    "last_hidden_state",
]
DEFAULT_MAX_LENGTH = 512
MAX_SUPPORTED_LENGTH = 8192


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--model-dir")
    parser.add_argument("--profile", default="{}")
    return parser.parse_args()


def resolve_model_path(model_dir):
    for relative in MODEL_CANDIDATES:
        candidate = os.path.join(model_dir, relative)
        if os.path.exists(candidate):
            return candidate
    raise RuntimeError(f"no ONNX model found in {model_dir}")


def validate_supported_inputs(inputs):
    unsupported = [entry.name for entry in inputs if entry.name not in ("input_ids", "attention_mask", "token_type_ids")]
    if not unsupported:
        return
    message = f"unsupported model inputs for text embedding API: {', '.join(unsupported)}"
    if "pixel_values" in unsupported:
        message += ". This looks like a multimodal graph. Provide a text-only export (for example onnx/text_model.onnx)."
    raise RuntimeError(message)


def resolve_output_name(outputs):
    output_names = [entry.name for entry in outputs]
    if not output_names:
        raise RuntimeError("model has no outputs")
    for preferred in OUTPUT_PREFERENCES:
        for name in output_names:
            lower = name.lower()
            if lower == preferred or lower.endswith("/" + preferred):
                return name
    return output_names[0]


def read_json(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (json.JSONDecodeError, OSError, TypeError):
        return {}


def parse_positive_length(value):
    if isinstance(value, int):
        parsed = value
    elif isinstance(value, float):
        parsed = int(value)
    elif isinstance(value, str) and value.isdigit():
        parsed = int(value)
    else:
        return None
    return parsed if parsed > 0 else None


def read_tokenizer_profile(model_dir):
    tokenizer_config = read_json(os.path.join(model_dir, "tokenizer_config.json"))
    tokenizer_json = read_json(os.path.join(model_dir, "tokenizer.json"))

    candidates = []
    for key in ("max_length", "model_max_length"):
        value = parse_positive_length(tokenizer_config.get(key))
        if value:
            candidates.append(min(value, MAX_SUPPORTED_LENGTH))

    truncation_length = parse_positive_length(tokenizer_json.get("truncation", {}).get("max_length"))
    if truncation_length:
        candidates.append(min(truncation_length, MAX_SUPPORTED_LENGTH))

    fixed_padding = parse_positive_length(tokenizer_json.get("padding", {}).get("strategy", {}).get("Fixed"))
    if fixed_padding:
        candidates.append(min(fixed_padding, MAX_SUPPORTED_LENGTH))

    default_max_length = min(candidates) if candidates else DEFAULT_MAX_LENGTH
    return {
        "default_max_length": max(default_max_length, 1),
        "fixed_padding_length": fixed_padding,
    }


def pad_to_max(values, max_len):
    trimmed = list(values[:max_len])
    return trimmed + [0] * (max_len - len(trimmed))


def mean_pool(hidden_states, attention_mask):
    pooled = []
    for token_rows, mask_row in zip(hidden_states, attention_mask):
        dim = len(token_rows[0])
        sums = [0.0] * dim
        weight_sum = 0.0
        for token_vector, weight in zip(token_rows, mask_row):
            if weight <= 0:
                continue
            weight_sum += float(weight)
            for index, value in enumerate(token_vector):
                sums[index] += float(value) * float(weight)
        if weight_sum > 0:
            inv = 1.0 / weight_sum
            sums = [value * inv for value in sums]
        pooled.append(sums)
    return pooled


def normalize_l2(vectors):
    output = []
    for row in vectors:
        norm = math.sqrt(sum(float(value) * float(value) for value in row))
        if norm == 0:
            output.append([float(value) for value in row])
            continue
        inv = 1.0 / norm
        output.append([float(value) * inv for value in row])
    return output


class TextEncoder:
    def __init__(self, model_dir, profile):
        import numpy as np
        import onnxruntime as ort
        from tokenizers import Tokenizer

        self.np = np
        self.tokenizer = Tokenizer.from_file(os.path.join(model_dir, "tokenizer.json"))
        self.tokenizer.no_padding()
        self.tokenizer.no_truncation()

        session_options = ort.SessionOptions()
        session_options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        session_options.intra_op_num_threads = int(profile.get("intra_threads", 1))
        session_options.inter_op_num_threads = int(profile.get("inter_threads", 1))

        self.session = ort.InferenceSession(
            resolve_model_path(model_dir),
            sess_options=session_options,
            providers=["CPUExecutionProvider"],
        )
        self.input_names = [entry.name for entry in self.session.get_inputs()]
        validate_supported_inputs(self.session.get_inputs())
        self.output_name = resolve_output_name(self.session.get_outputs())
        self.output_rank = len(next(entry.shape for entry in self.session.get_outputs() if entry.name == self.output_name))

        tokenizer_profile = read_tokenizer_profile(model_dir)
        self.max_length = tokenizer_profile["default_max_length"]
        self.fixed_padding_length = tokenizer_profile["fixed_padding_length"]

    def embed(self, texts):
        rows = [str(text) for text in texts]
        encodings = self.tokenizer.encode_batch(rows)
        feeds = self.build_feeds(encodings)
        output = self.session.run([self.output_name], feeds)[0]

        if self.output_rank == 2:
            vectors = output.tolist()
        elif self.output_rank == 3:
            if "attention_mask" not in feeds:
                raise RuntimeError("mean pooling requires attention_mask input")
            vectors = mean_pool(output.tolist(), feeds["attention_mask"].tolist())
        else:
            raise RuntimeError(f"unsupported output rank {self.output_rank}")
        return normalize_l2(vectors)

    def build_feeds(self, encodings):
        if self.fixed_padding_length:
            max_len = min(self.max_length, self.fixed_padding_length)
        else:
            longest = max((len(encoding.ids) for encoding in encodings), default=0)
            max_len = min(longest, self.max_length)

        feeds = {
            "input_ids": self.np.array(
                [pad_to_max(encoding.ids, max_len) for encoding in encodings],
                dtype=self.np.int64,
            )
        }

        if "attention_mask" in self.input_names:
            feeds["attention_mask"] = self.np.array(
                [pad_to_max(encoding.attention_mask, max_len) for encoding in encodings],
                dtype=self.np.int64,
            )
        if "token_type_ids" in self.input_names:
            feeds["token_type_ids"] = self.np.array(
                [pad_to_max(encoding.type_ids, max_len) for encoding in encodings],
                dtype=self.np.int64,
            )
        return feeds


def run_check():
    import numpy  # noqa: F401
    import onnxruntime  # noqa: F401
    import tokenizers  # noqa: F401

    print("python_onnxruntime ready")


def run_server(model_dir, profile):
    encoder = TextEncoder(model_dir, profile)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        request = json.loads(line)
        try:
            if request.get("action") != "embed":
                raise RuntimeError("unsupported action")
            response = {"embeddings": encoder.embed(request.get("texts", []))}
        except Exception as exc:  # noqa: BLE001
            response = {"error": str(exc)}
        sys.stdout.write(json.dumps(response) + "\n")
        sys.stdout.flush()


def main():
    args = parse_args()
    if args.check:
        run_check()
        return 0
    if args.serve:
        if not args.model_dir:
            raise RuntimeError("--model-dir is required with --serve")
        run_server(args.model_dir, json.loads(args.profile))
        return 0
    raise RuntimeError("expected --check or --serve")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(str(exc) + "\n")
        raise SystemExit(1)
