#!/usr/bin/env bash
# Linux type-check harness for the KlimaBilanz iOS app. See tools/typecheck/README.md.
#   tools/typecheck/run.sh [--src <repo-root>] [--target app|widgets|all] [--warnings] [--notes] [-v]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/run.py" "$@"
