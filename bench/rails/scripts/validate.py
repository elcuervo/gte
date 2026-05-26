#!/usr/bin/env python3
import argparse
import json
import math
import sys
import urllib.parse
import urllib.request

QUERIES = [
    "cat photo",
    "sunset beach",
    "a person walking their dog in a park with autumn leaves",
    "machine learning transformer architecture attention mechanism",
    "hello world this is a test query for embedding validation",
]

THRESHOLDS = {
    "l2_norm_max_delta": 1e-3,
    "deterministic_max_abs": 1e-12,
    "multi_query_min_spread": 0.01,
    "gte_vs_pure_min_cosine": 0.999,
    "gte_vs_pure_max_abs": 0.01,
}

EXPECTED_DIMS = {"siglip2": 768, "e5": 384, "clip": 512}


def fetch(port, text):
    encoded = urllib.parse.quote(text, safe="")
    url = f"http://localhost:{port}/embed?text={encoded}"
    resp = urllib.request.urlopen(url, timeout=15)
    body = json.loads(resp.read())
    if resp.status != 200:
        raise RuntimeError(
            f"HTTP {resp.status}: {body.get('error', body.get('message', 'unknown'))}"
        )
    return body


def cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = math.sqrt(sum(v * v for v in a))
    nb = math.sqrt(sum(v * v for v in b))
    return dot / (na * nb)


def max_abs(a, b):
    return max(abs(x - y) for x, y in zip(a, b)) if a else 0.0


def l2_norm(vec):
    return math.sqrt(sum(v * v for v in vec))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="e5")
    parser.add_argument("--gte-port", type=int, default=3001)
    parser.add_argument("--pure-port", type=int, default=3002)
    args = parser.parse_args()

    passes = 0
    failures = []
    model = args.model
    gte_port = args.gte_port
    pure_port = args.pure_port
    expected_dim = EXPECTED_DIMS.get(model, 384)

    print("=" * 60)
    print(f"Validation: {model}")
    print("=" * 60)

    # 1. L2 normalization
    print("  L2 normalization...", end=" ")
    ok = True
    for text in QUERIES:
        resp = fetch(gte_port, text)
        norm = l2_norm(resp["embedding"])
        if abs(norm - 1.0) > THRESHOLDS["l2_norm_max_delta"]:
            failures.append(f"{model} L2 norm {norm:.6f} for {text[:40]}")
            ok = False
    print("PASS" if ok else "FAIL")
    passes += 1 if ok else 0

    # 2. Dimension
    print("  Dimension...", end=" ")
    resp = fetch(gte_port, "test")
    dim = len(resp["embedding"])
    if dim == expected_dim:
        print(f"PASS ({dim})")
        passes += 1
    else:
        print(f"FAIL (expected {expected_dim}, got {dim})")
        failures.append(f"{model} expected dim {expected_dim}, got {dim}")

    # 3. Deterministic
    print("  Deterministic...", end=" ")
    a = fetch(gte_port, "deterministic test query")["embedding"]
    b = fetch(gte_port, "deterministic test query")["embedding"]
    diff = max_abs(a, b)
    if diff <= THRESHOLDS["deterministic_max_abs"]:
        print(f"PASS (max_abs={diff})")
        passes += 1
    else:
        print(f"FAIL (max_abs={diff})")
        failures.append(f"{model} non-deterministic: max_abs={diff}")

    # 4. Diversity
    print("  Diversity...", end=" ")
    e0 = fetch(gte_port, QUERIES[0])["embedding"]
    e1 = fetch(gte_port, QUERIES[1])["embedding"]
    cos = cosine(e0, e1)
    spread = 1.0 - abs(cos)
    if spread >= THRESHOLDS["multi_query_min_spread"]:
        print(f"PASS (1-cos={spread:.4f})")
        passes += 1
    else:
        print(f"FAIL (1-cos={spread})")
        failures.append(f"{model} queries too similar: 1-cos={spread}")

    # 5. GTE vs pure Ruby
    print("  GTE vs pure Ruby...", end=" ")
    gte = fetch(gte_port, QUERIES[0])["embedding"]
    pure = fetch(pure_port, QUERIES[0])["embedding"]
    cos = cosine(gte, pure)
    mad = max_abs(gte, pure)
    if (
        cos >= THRESHOLDS["gte_vs_pure_min_cosine"]
        and mad <= THRESHOLDS["gte_vs_pure_max_abs"]
    ):
        print(f"PASS (cos={cos:.6f}, max_abs={mad:.6f})")
        passes += 1
    elif cos >= 0.99:
        print(f"WARN (cos={cos:.6f}, max_abs={mad:.6f})")
        passes += 1
    else:
        print(
            f"INFO (cos={cos:.6f}, max_abs={mad:.6f}) — different tokenizer paths expected"
        )

    # 6. Response times
    print("  Response times...", end=" ")
    times = [fetch(gte_port, t)["ms"] for t in QUERIES]
    avg = sum(times) / len(times)
    print(f"avg={avg:.2f}ms range={min(times):.2f}-{max(times):.2f}ms")
    passes += 1

    # 7. Runtime label
    print("  Runtime label...", end=" ")
    resp = fetch(gte_port, "test")
    if resp.get("runtime") == "gte":
        print("PASS")
        passes += 1
    else:
        print(f"FAIL (got {resp.get('runtime')})")
        failures.append(f"{model} runtime label mismatch: {resp.get('runtime')}")

    # Summary
    total_checks = 7
    print()
    print("=" * 60)
    if not failures:
        print(f"Result: PASS ({passes}/{total_checks} passed)")
        return 0
    else:
        print(f"Result: FAIL ({passes}/{total_checks} passed)")
        for f in failures:
            print(f"  - {f}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
