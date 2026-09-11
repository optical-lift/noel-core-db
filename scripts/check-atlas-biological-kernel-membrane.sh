#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
files=(supabase/migrations/*atlas_biological_kernel*.sql)

if [ ${#files[@]} -eq 0 ]; then
  echo "Atlas biological kernel membrane FAILED: no kernel migration source found."
  exit 1
fi

# The biological kernel may read biological/production evidence only. These are
# execution, routing, presentation, spatial-release, or materialized-consequence
# identifiers and are forbidden inside kernel source.
forbidden='atlas\.tasks|atlas\.task_|task_crop_cycles|task_outcome_events|weekly_harvest_task_results|planned_work_occurrences|state_consequence_|worker_day_|home_task_|farm_hand|crop_destination_claim|task_required_resources|production_transplant_gate|external_readiness|visibility_scope|capacity_|flower_demand|flower_sale|buyer_contact|weather_'

failed=0
for file in "${files[@]}"; do
  if grep -Ein "$forbidden" "$file"; then
    echo "Atlas biological kernel membrane FAILED in $file: forbidden execution/presentation dependency found."
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "Atlas biological kernel membrane passed: kernel source is isolated from execution, routing, presentation, spatial-release, and materialized-consequence dependencies."
