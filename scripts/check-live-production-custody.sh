#!/usr/bin/env bash
set -euo pipefail

# Compatibility entrypoint. The canonical implementation lives in
# reconcile-live-production-custody.{sh,py}; do not add classification logic here.
exec bash scripts/reconcile-live-production-custody.sh --enforce
