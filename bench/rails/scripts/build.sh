#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Building GTE Rails benchmark image ==="
docker compose build --no-cache 2>&1
echo "=== Build complete ==="
echo "Image: gte-bench:latest"
echo "Architecture: $(docker inspect gte-bench:latest --format '{{.Architecture}}')"
