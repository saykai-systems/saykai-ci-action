#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="${1:?RUNNER_REPO required (ex: saykai-systems/runner)}"
RUNNER_VERSION="${2:?RUNNER_VERSION required (ex: v0.1.1 or latest)}"
RUNNER_BASE_URL="${3:-}"   # optional, ex: https://downloads.saykai.com/runner
DEST_PATH="${4:?DEST_PATH required}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux|darwin) ;;
  *)
    echo "Unsupported OS: ${OS}" >&2
    exit 1
    ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported arch: ${ARCH}" >&2
    exit 1
    ;;
esac

ASSET_NAME="saykai-runner-${OS}-${ARCH}"

mkdir -p "$(dirname "$DEST_PATH")"

download_from_base_url() {
  local base="$1"
  local version="$2"
  local url="${base%/}/${version}/${ASSET_NAME}"

  echo "Downloading runner from base URL: ${url}"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp"
  if [[ ! -s "$tmp" ]]; then
    echo "ERROR: Download produced an empty file from base URL." >&2
    rm -f "$tmp"
    exit 1
  fi
  mv "$tmp" "$DEST_PATH"
}

github_api_get() {
  local url="$1"
  local token="$2"

  local tmp
  tmp="$(mktemp)"

  # Capture HTTP status without relying on curl -f (so we can print the body on failure).
  local code
  code="$(curl -sS -L -o "$tmp" -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$url")"

  if [[ "$code" -lt 200 || "$code" -ge 300 ]]; then
    echo "ERROR: GitHub API request failed (${code}) for ${url}" >&2
    echo "Response (first 300 chars):" >&2
    head -c 300 "$tmp" >&2 || true
    echo >&2
    rm -f "$tmp"
    exit 1
  fi

  cat "$tmp"
  rm -f "$tmp"
}

download_from_github_release() {
  local repo="$1"
  local version="$2"
  local token="${SAYKAI_RUNNER_TOKEN:-}"

  if [[ -z "$token" ]]; then
    echo "Missing SAYKAI_RUNNER_TOKEN. For private GitHub releases you must provide a token with read access to ${repo}." >&2
    echo "Pass it as action input runner_token: \${{ secrets.SAYKAI_RUNNER_TOKEN }}" >&2
    exit 1
  fi

  local api_base="https://api.github.com/repos/${repo}/releases"
  local release_url

  if [[ "$version" == "latest" ]]; then
    echo "Resolving latest release for ${repo}..."
    release_url="${api_base}/latest"
  else
    echo "Resolving release tag ${version} for ${repo}..."
    release_url="${api_base}/tags/${version}"
  fi

  local release_json
  release_json="$(github_api_get "$release_url" "$token")"

  # Find our asset id from the release JSON (no heredocs, no bash parsing traps)
  local asset_id
  asset_id="$(python3 -c '
import json,sys
name=sys.argv[1]
data=json.load(sys.stdin)
for a in data.get("assets", []):
  if a.get("name") == name:
    print(a.get("id"))
    raise SystemExit(0)
raise SystemExit(1)
' "$ASSET_NAME" <<<"$release_json")" || {
    echo "ERROR: Could not find asset '${ASSET_NAME}' in release ${version} for ${repo}" >&2
    echo "Available assets:" >&2
    python3 -c '
import json,sys
data=json.load(sys.stdin)
for a in data.get("assets", []):
  n=a.get("name")
  if n: print(n)
' <<<"$release_json" >&2 || true
    exit 1
  }

  local asset_url="https://api.github.com/repos/${repo}/releases/assets/${asset_id}"
  echo "Downloading runner asset '${ASSET_NAME}' from GitHub (asset id: ${asset_id})..."

  local tmp
  tmp="$(mktemp)"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$asset_url" -o "$tmp"

  if [[ ! -s "$tmp" ]]; then
    echo "ERROR: Downloaded runner is empty." >&2
    rm -f "$tmp"
    exit 1
  fi

  mv "$tmp" "$DEST_PATH"
}

validate_download() {
  if [[ ! -s "$DEST_PATH" ]]; then
    echo "ERROR: Runner not downloaded to ${DEST_PATH}" >&2
    exit 1
  fi

  # Catch common failure modes (HTML login page, JSON error, etc.)
  if command -v file >/dev/null 2>&1; then
    local ft
    ft="$(file -b "$DEST_PATH" || true)"
    echo "Runner file type: ${ft}"
    if [[ "$ft" == *"HTML"* || "$ft" == *"JSON"* || "$ft" == *"ASCII text"* ]]; then
      echo "ERROR: Downloaded runner does not look like a binary. Check token permissions and the release asset name." >&2
      exit 1
    fi
  fi
}

if [[ -n "$RUNNER_BASE_URL" ]]; then
  # Base URL mode expects: /<version>/<asset>
  if [[ "$RUNNER_VERSION" == "latest" ]]; then
    echo "runner_base_url provided but runner_version=latest is not supported for base URL mode." >&2
    echo "Use an explicit version tag like v0.1.1" >&2
    exit 1
  fi
  download_from_base_url "$RUNNER_BASE_URL" "$RUNNER_VERSION"
else
  download_from_github_release "$RUNNER_REPO" "$RUNNER_VERSION"
fi

chmod +x "$DEST_PATH"
validate_download
echo "Runner installed at: $DEST_PATH"
