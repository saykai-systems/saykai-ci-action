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

# Run from the workspace so relative paths (spec/out) behave predictably
cd "$WORK_DIR"

# Install runner
bash "${ACTION_DIR}/install-runner.sh" \
  "$RUNNER_REPO" \
  "$RUNNER_VERSION" \
  "$RUNNER_BASE_URL" \
  "$RUNNER_PATH"

# Optional verification (safe to keep even if you don't have checksums yet)
bash "${ACTION_DIR}/verify-runner.sh" "$RUNNER_PATH" || true

write_step_summary() {
  local rc="$1"

  # If GitHub step summary isn't available, do nothing
  if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    return 0
  fi

  {
    echo "## Saykai Safety Gate"
    echo ""
    echo "**Exit code:** ${rc}"
    echo "**Spec:** \`${SPEC_PATH}\`"
    echo "**Output:** \`${OUT_PATH}\`"
    echo ""
  } >> "$GITHUB_STEP_SUMMARY"

  if [[ -f "$OUT_PATH" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$OUT_PATH" >> "$GITHUB_STEP_SUMMARY" <<'PY'
import json,sys

path=sys.argv[1]
with open(path,"r",encoding="utf-8") as f:
  d=json.load(f)

decision=d.get("decision","UNKNOWN")
runner=d.get("runner",{}) or {}
summary=d.get("summary",{}) or {}

print(f"**Decision:** {decision}")
print(f"**Runner version:** {runner.get('version','?')}")

commit = runner.get("commit") or runner.get("sha")
if commit:
  print(f"**Runner commit:** {commit}")

spec = summary.get("spec_path")
if spec is not None:
  print(f"**Spec path (reported):** {spec}")

msg = summary.get("message")
if msg:
  print("")
  print("### Summary")
  print(str(msg))
PY
    else
      {
        echo "_safety_pack.json exists but python3 is unavailable to render a summary._"
        echo ""
      } >> "$GITHUB_STEP_SUMMARY"
    fi
  else
    {
      echo "_No safety pack file found at the expected path. Runner may have failed before writing output._"
      echo ""
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# Run (capture exit code so we can always write a summary)
echo "Running Saykai runner..."
set +e
"$RUNNER_PATH" run --spec "$SPEC_PATH" --out "$OUT_PATH"
RC=$?
set -e

echo "Saykai completed. Output: $OUT_PATH"
write_step_summary "$RC"

# Preserve runner exit code
exit "$RC"
