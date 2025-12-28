# Saykai CI Safety Gate (GitHub Action)

Saykai adds a CI “safety gate” to your GitHub Actions workflow. It runs your Saykai Runner against a spec (`saykai.yml`) and produces a Safety Pack artifact plus a readable run summary.

## What you get
- A required CI check that can PASS or BLOCK
- A machine-readable `safety_pack.json`
- A human-readable run summary in the GitHub Actions UI

## Quick start (5 minutes)

### 1) Add a spec file at repo root
Create `saykai.yml` in your repo:

```yaml
version: "v1"
project: "my-repo"
ci_gate:
  require_files:
    - README.md
notes:
  - "Pilot spec"
