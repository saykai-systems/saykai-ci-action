#!/usr/bin/env bash
set -euo pipefail

RUNNER_REPO="$1"         # saykai-systems/runner
RUNNER_VERSION="$2"      # v0.1.0 or latest
RUNNER_BASE_URL="$3"     # optional, e.g. https://downloads.saykai.com/runner
DEST_PATH="$4"           # e.g. /home/runner/work/.../.saykai/bin/saykai

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported arch: $ARCH"
    exit 1
    ;;
esac

ASSET_NAME="saykai-runner-${OS}-${ARCH}"

download_from_base_url() {
  local base="$1"
  local version="$2"
  local url="${base%/}/${version}/${ASSET_NAME}"
  echo "Downloading runner from: $url"
  curl -fsSL "$url" -o "$DEST_PATH"
}

download_from_github_release() {
  local repo="$1"
  local version="$2"
  local token="${SAYKAI_RUNNER_TOKEN:-}"

  if [[ -z "$token" ]]; then
    echo "Missing SAYKAI_RUNNER_TOKEN. For private GitHub releases you must provide a token with read access to ${repo}."
    echo "Pass it as action input runner_token: \${{ secrets.SAYKAI_RUNNER_TOKEN }}"
    exit 1
  fi

  local api="https://api.github.com/repos/${repo}/releases"
  local release_json

  if [[ "$version" == "latest" ]]; then
    echo "Resolving latest release for ${repo}..."
    release_json="$(curl -fsSL -H "Authorization: Bearer ${token}" -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api}/latest")"
  else
    echo "Resolving release tag ${version} for ${repo}..."
    release_json="$(curl -fsSL -H "Authorization: Bearer ${token}" -H "X-GitHub-Api-Version: 2022-11-28" \
      "${api}/tags/${version}")"
  fi
  # --- DEBUG: validate GitHub API response ---
if [[ -z "$release_json" ]]; then
  echo "ERROR: Empty response from GitHub API"
  exit 1
fi

# Optional but very helpful
if [[ "${release_json:0:1}" != "{" ]]; then
  echo "ERROR: GitHub API did not return JSON"
  echo "First 300 chars of response:"
  echo "${release_json:0:300}"
  exit 1
fi
# --- END DEBUG ---

    # Extract the asset id for our target asset name
  local asset_id
  asset_id="$(
    python - "$ASSET_NAME" <<'PY'
import json,sys
name=sys.argv[1]
data=json.load(sys.stdin)
for a in data.get("assets", []):
    if a.get("name") == name:
        print(a.get("id"))
        raise SystemExit(0)
raise SystemExit(1)
PY
  <<<"$release_json"
  )" || {
    echo "Could not find asset '${ASSET_NAME}' in release ${version} for ${repo}"
    echo "Release response (first 300 chars): ${release_json:0:300}"
    exit 1
  }

import json,sys
data=json.load(sys.stdin)
name=sys.argv[1]
assets=data.get("assets",[])
for a in assets:
  if a.get("name")==name:
    print(a.get("id"))
    sys.exit(0)
sys.exit(1)
PY
"$ASSET_NAME" <<<"$release_json")" || {
    echo "Could not find asset '${ASSET_NAME}' in release ${version} for ${repo}"
    exit 1
  }

  local asset_url="https://api.github.com/repos/${repo}/releases/assets/${asset_id}"
  echo "Downloading runner asset '${ASSET_NAME}' from GitHub (asset id: ${asset_id})..."

  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$asset_url" -o "$DEST_PATH"
}

if [[ -n "$RUNNER_BASE_URL" ]]; then
  # Base URL mode: expects /<version>/<asset>
  if [[ "$RUNNER_VERSION" == "latest" ]]; then
    echo "runner_base_url provided but runner_version=latest is not supported for base URL mode."
    echo "Use an explicit version tag like v0.1.0"
    exit 1
  fi
  download_from_base_url "$RUNNER_BASE_URL" "$RUNNER_VERSION"
else
  download_from_github_release "$RUNNER_REPO" "$RUNNER_VERSION"
fi

chmod +x "$DEST_PATH"
echo "Runner installed at: $DEST_PATH"
