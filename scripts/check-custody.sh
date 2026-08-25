#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "schemas/OWNERSHIP.md" ]; then
  echo "Missing schemas/OWNERSHIP.md"
  exit 1
fi

if [ ! -d "supabase/migrations" ]; then
  echo "Missing supabase/migrations"
  exit 1
fi

bad=0
while IFS= read -r file; do
  base="$(basename "$file")"
  if [[ "$base" == "README.md" ]]; then
    continue
  fi
  if [[ ! "$base" =~ ^[0-9]{14}_(core|atlas|wnph|shared|project)_ ]]; then
    echo "Migration lacks an explicit owner prefix: $file"
    bad=1
  fi
done < <(find supabase/migrations -maxdepth 1 -type f | sort)

if [ "$bad" -ne 0 ]; then
  exit 1
fi

echo "Database custody checks passed."
