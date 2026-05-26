#!/usr/bin/env bash
# Usage: ./validate.sh [model]
set -euo pipefail
cd "$(dirname "$0")/.."

MODEL="${1:-}"

if [ -n "$MODEL" ]; then
  MODELS=("$MODEL")
else
  MODELS=(siglip2 e5)
fi

ALL_PASS=true

for model in "${MODELS[@]}"; do
  echo ""
  echo "============================================================"
  echo " Validating: $model"
  echo "============================================================"
  echo ""

  MODEL="$model" docker compose up -d --wait 2>&1
  sleep 2

  echo ""
  python3 scripts/validate.py --model "$model" --gte-port 3001 --pure-port 3002 2>&1
  RESULT=$?

  docker compose down 2>&1

  if [ $RESULT -ne 0 ]; then
    ALL_PASS=false
  fi
done

echo ""
echo "============================================================"
if $ALL_PASS; then
  echo " Overall: PASS"
  exit 0
else
  echo " Overall: FAIL"
  exit 1
fi
echo "============================================================"
