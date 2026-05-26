#!/usr/bin/env bash
# Usage: ./sweep.sh <model> [duration_s]
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-siglip2}"
DURATION="${2:-30}"
CONCURRENCIES=(1 2 4 8 16 32)

echo "============================================================"
echo " Sweep: $MODEL  (${DURATION}s)"
echo "============================================================"

echo ""
echo ">>> Starting containers for $MODEL..."
MODEL="$MODEL" docker compose up -d --wait 2>&1
echo ""

sleep 2

for c in "${CONCURRENCIES[@]}"; do
  echo "--- Concurrency $c ---"
  for rt in gte pure-ruby; do
    ./scripts/stress.sh "$rt" "$MODEL" "$c" "$DURATION"
  done

  GTE_FILE="results/${MODEL}_gte_c${c}.json"
  PURE_FILE="results/${MODEL}_pure-ruby_c${c}.json"

  if [ -f "$GTE_FILE" ] && [ -f "$PURE_FILE" ]; then
    echo ""
    echo "  Comparison at c=$c:"
    python3 -c "
import json
with open('${GTE_FILE}') as f: g = json.load(f)
with open('${PURE_FILE}') as f: p = json.load(f)
gte_p90 = float(g.get('latency_p90_ms', 0))
pure_p90 = float(p.get('latency_p90_ms', 0))
ratio = round(pure_p90 / gte_p90, 2) if gte_p90 > 0 else 0
winner = 'gte' if ratio >= 1.0 else 'pure_ruby'
print(f'    gte p90={gte_p90:.2f}ms  pure_ruby p90={pure_p90:.2f}ms  ratio={ratio:.2f}x  faster={winner}')

comp = {
  'model': '${MODEL}',
  'concurrency': ${c},
  'gte_p90_ms': gte_p90,
  'pure_ruby_p90_ms': pure_p90,
  'p90_ratio': ratio,
  'faster': winner
}
with open('results/${MODEL}_comparison_c${c}.json', 'w') as f:
  json.dump(comp, f, indent=2)
    "
    echo ""
  fi
done

echo ">>> Stopping containers..."
docker compose down 2>&1

echo ""
echo "============================================================"
echo " Sweep complete: $MODEL"
echo " Results: results/${MODEL}_*.json"
echo "============================================================"
