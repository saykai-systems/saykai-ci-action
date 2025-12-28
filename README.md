 # Saykai Runner Contract (v0)

## CLI
The runner must support:

- `saykai-runner run --spec <path> --out <path>`
- `saykai-runner --version` (optional)

## Exit Codes
- `0` = PASS
- `2` = BLOCK (safety violation)
- `1` = ERROR (runner failure)

## Outputs
On every successful execution (PASS or BLOCK), the runner must write:

- `<out>` JSON (Safety Pack)

Minimum fields required in the JSON:
- `version`
- `decision` (PASS|BLOCK)
- `timestamp`
- `summary` (object)
