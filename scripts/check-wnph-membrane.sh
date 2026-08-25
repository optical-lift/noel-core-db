#!/usr/bin/env bash
set -euo pipefail

mapfile -t files < <(find supabase/migrations -maxdepth 1 -type f -name '*_wnph_product_schema_membrane_v1.sql' | sort)

if [ "${#files[@]}" -ne 1 ]; then
  echo "Expected exactly one WNPH product schema membrane migration; found ${#files[@]}."
  printf '%s\n' "${files[@]:-}"
  exit 1
fi

file="${files[0]}"

required_patterns=(
  "create schema if not exists wnph authorization postgres;"
  "create schema if not exists wnph_api authorization postgres;"
  "revoke all on schema wnph from public, anon, authenticated, service_role;"
  "revoke all on schema wnph_api from public, anon, authenticated, service_role;"
  "alter default privileges in schema wnph revoke all on tables from public, anon, authenticated, service_role;"
  "alter default privileges in schema wnph_api revoke all on functions from public, anon, authenticated, service_role;"
  "has_schema_privilege(role_name, 'wnph', 'USAGE')"
  "has_schema_privilege(role_name, 'wnph_api', 'USAGE')"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$file"; then
    echo "WNPH membrane contract missing required source assertion in $file:"
    echo "  $pattern"
    exit 1
  fi
done

echo "WNPH product schema membrane source contract passed: canonical and API schemas are closed by default."
