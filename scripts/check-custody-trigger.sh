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
  echo "Custody workflow must retain the exact global live production source verifier."
  exit 1
}

if grep -Fq 'continue-on-error: true' "$workflow"; then
  echo "Live custody verification must be blocking; continue-on-error is forbidden in the custody workflow."
  exit 1
fi

grep -Fq 'run: bash scripts/check-live-production-custody-lane.sh atlas' "$workflow" || {
  echo "Custody workflow must verify the Atlas production release lane."
  exit 1
}

grep -Fq 'run: bash scripts/check-live-production-custody-lane.sh wnph' "$workflow" || {
  echo "Custody workflow must verify the WNPH production release lane."
  exit 1
}

echo "Custody trigger contract passed: Git events, 15-minute production watch, manual verification, blocking global custody verification, and product release-lane verification are enabled."
