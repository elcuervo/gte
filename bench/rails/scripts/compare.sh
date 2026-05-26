#!/usr/bin/env bash
# Usage: ./compare.sh [duration_s]
# Runs all 3 models
set -euo pipefail
cd "$(dirname "$0")/.."

DURATION="${1:-30}"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
SUMMARY="results/full_sweep_${TIMESTAMP}.json"

echo "============================================================"
echo " Full Comparison Sweep: All Models"
echo " Duration: ${DURATION}s"
echo " Started: $(date)"
echo "============================================================"

for model in siglip2 e5 clip; do
  echo ""
  echo "============================================================"
  echo " MODEL: $model"
  echo "============================================================"
  ./scripts/sweep.sh "$model" "$DURATION"
done

echo ""
echo ">>> Aggregating results..."
ruby -r json -e "
summary = {
  timestamp: '${TIMESTAMP}',
  duration_s: ${DURATION},
  models: {}
}

%w[siglip2 e5 clip].each do |model|
  model_data = { label: model, concurrency_levels: [] }
  [1, 2, 4, 8, 16, 32].each do |c|
    comp_file = \"results/#{model}_comparison_c#{c}.json\"
    next unless File.exist?(comp_file)
    comp = JSON.parse(File.read(comp_file))
    model_data[:concurrency_levels] << comp
  end
  summary[:models][model] = model_data
end

File.write('${SUMMARY}', JSON.pretty_generate(summary))
puts \"Wrote: ${SUMMARY}\"
" 2>&1

echo ""
echo "============================================================"
echo " Full sweep complete"
echo " Summary: $SUMMARY"
echo "============================================================"
