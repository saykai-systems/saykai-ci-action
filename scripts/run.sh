#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="${1:-saykai-systems/runner}"
RUNNER_VERSION="${2:-latest}"
RUNNER_BASE_URL="${3:-}"
SPEC_PATH="${4:-saykai.yml}"
OUT_PATH="${5:-safety_pack.json}"

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
BIN_DIR="${WORK_DIR}/.saykai/bin"
RUNNER_PATH="${BIN_DIR}/saykai"

mkdir -p "$BIN_DIR"

# Install runner
"${ACTION_DIR}/install-runner.sh" \
  "$RUNNER_REPO" \
  "$RUNNER_VERSION" \
  "$RUNNER_BASE_URL" \
  "$RUNNER_PATH"

# Optional verification (safe to keep even if you don't have checksums yet)
"${ACTION_DIR}/verify-runner.sh" "$RUNNER_PATH" || true

# Run
echo "Running Saykai runner..."
"$RUNNER_PATH" run --spec "$SPEC_PATH" --out "$OUT_PATH"
echo "Saykai completed. Output: $OUT_PATH"
