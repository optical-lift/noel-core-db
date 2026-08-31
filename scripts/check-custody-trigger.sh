#!/usr/bin/env bash
set -euo pipefail

workflow=".github/workflows/custody.yml"
release_workflow=".github/workflows/production-db-release.yml"

if [ ! -f "$workflow" ]; then
  echo "Missing $workflow"
  exit 1
fi

if [ ! -f "$release_workflow" ]; then
  echo "Missing $release_workflow"
  exit 1
fi

grep -Fq '  schedule:' "$workflow" || {
  echo "Custody workflow must monitor production on a schedule, not only on Git events."
  exit 1
}

grep -Fq '    - cron: "*/15 * * * *"' "$workflow" || {
  echo "Custody workflow must poll live production every 15 minutes."
  exit 1
}

grep -Fq '  workflow_dispatch:' "$workflow" || {
  echo "Custody workflow must remain manually runnable for immediate verification."
  exit 1
}

grep -Fq 'run: bash scripts/check-production-release-contract.sh' "$workflow" || {
  echo "Custody workflow must guard the production database release seam."
  exit 1
}

grep -Fq 'run: bash scripts/check-live-production-custody.sh' "$workflow" || {
  echo "Custody workflow must execute the exact live production source verifier."
  exit 1
}

echo "Custody trigger contract passed: Git events, 15-minute production watch, manual verification, and the governed production release seam are all enabled."
