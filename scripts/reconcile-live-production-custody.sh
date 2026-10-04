#!/usr/bin/env bash
set -euo pipefail

api_url="${NOEL_CORE_SUPABASE_URL:-}"
publishable_key="${NOEL_CORE_SUPABASE_PUBLISHABLE_KEY:-}"
manifest_path="${LIVE_CUSTODY_MANIFEST_PATH:-/tmp/live-custody-reconciliation.json}"
mode="${1:---enforce}"

if [ -z "$api_url" ] || [ -z "$publishable_key" ]; then
  echo "NOEL_CORE_SUPABASE_URL and NOEL_CORE_SUPABASE_PUBLISHABLE_KEY are required."
  exit 2
fi

if [[ "$mode" != "--enforce" && "$mode" != "--report-only" ]]; then
  echo "Usage: $0 [--enforce|--report-only]"
  exit 2
fi

packet_file="$(mktemp)"
trap 'rm -f "$packet_file"' EXIT

curl --fail --silent --show-error \
  --request POST \
  --header "apikey: $publishable_key" \
  --header "Authorization: Bearer $publishable_key" \
  --header "Content-Type: application/json" \
  --data '{}' \
  "$api_url/rest/v1/rpc/shared_db_custody_release_packet_v1" \
  | tr -d '\r' > "$packet_file"

args=("$packet_file" --manifest "$manifest_path")
if [[ "$mode" == "--enforce" ]]; then
  args+=(--enforce)
fi

python3 scripts/reconcile-live-production-custody-with-supplements.py "${args[@]}"
