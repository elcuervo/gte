#!/usr/bin/env bash
# Usage: ./stress.sh <runtime> <model> <concurrency> [duration_s]
set -euo pipefail
cd "$(dirname "$0")/.."

RUNTIME="${1:-gte}"
MODEL="${2:-siglip2}"
CONC="${3:-16}"
DURATION="${4:-30}"
PORT="$([ "$RUNTIME" = "gte" ] && echo "${GTE_PORT:-3001}" || echo "${PURE_PORT:-3002}")"
RESULT_FILE="results/${MODEL}_${RUNTIME}_c${CONC}.json"
WARMUP_TEXT="benchmark warmup test query"

echo "=== Stress: $MODEL / $RUNTIME / c=$CONC / ${DURATION}s ==="
echo "  port: $PORT"

echo "  warmup..."
wrk -c2 -d10s "http://localhost:${PORT}/embed?text=${WARMUP_TEXT}" > /dev/null 2>&1 || true

echo "  running..."
THREADS=$(( CONC < 4 ? CONC : 4 ))
RAW=$(wrk -c"${CONC}" -t"${THREADS}" -d"${DURATION}s" --latency \
  -s stress/embed.lua \
  "http://localhost:${PORT}" 2>&1)

echo "$RAW"

REQUESTS=$(echo "$RAW" | grep "requests in" | awk '{print $1}')
THROUGHPUT=$(echo "$RAW" | grep "Requests/sec" | awk '{print $2}')
parse_ms() {
  local val="$1"
  case "$val" in
    *ms) echo "${val%ms}" ;;
    *s)  echo "${val%s} * 1000" | bc 2>/dev/null || echo "9999" ;;
    *)   echo "0" ;;
  esac
}

P50=$(parse_ms "$(echo "$RAW" | grep "50%" | head -1 | awk '{print $2}')")
P75=$(parse_ms "$(echo "$RAW" | grep "75%" | head -1 | awk '{print $2}')")
P90=$(parse_ms "$(echo "$RAW" | grep "90%" | head -1 | awk '{print $2}')")
P99=$(parse_ms "$(echo "$RAW" | grep "99%" | head -1 | awk '{print $2}')")
NON_2XX=$(echo "$RAW" | grep "Non-2xx" | awk '{print $NF}' || echo "0")

python3 -c "
import json
print(json.dumps({
  'model': '${MODEL}',
  'runtime': '${RUNTIME}',
  'concurrency': ${CONC},
  'duration_s': ${DURATION},
  'requests': ${REQUESTS:-0},
  'throughput_rps': ${THROUGHPUT:-0},
  'latency_p50_ms': ${P50:-0},
  'latency_p75_ms': ${P75:-0},
  'latency_p90_ms': ${P90:-0},
  'latency_p99_ms': ${P99:-0},
  'non_2xx': ${NON_2XX:-0}
}, indent=2))
" > "$RESULT_FILE"

echo "  wrote: $RESULT_FILE"
