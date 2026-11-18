#!/usr/bin/env bash
# HELD TITUS U1 real local GoTrue/PostgREST, fictional source only.
# NO production dump, production database, secrets, external RPC or release.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || exit 2
for command_name in supabase psql python3 docker timeout; do
  command -v "$command_name" >/dev/null || { echo "Missing $command_name" >&2; exit 2; }
done
[[ "$(supabase --version | tail -n 1)" == "2.116.0" ]] || {
  echo "Local signed probe requires pinned Supabase CLI v2.116.0" >&2
  exit 2
}
# A hosted connection is NEVER a test dependency.
for env_name in NOEL_CORE_DATABASE_URL SUPABASE_DB_URL DATABASE_URL SUPABASE_ACCESS_TOKEN; do
  if [[ -n "${!env_name:-}" ]]; then
    echo "Refusing environment with remote DB/management credentials" >&2
    exit 2
  fi
done
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
d="$root/candidates/shared-teaching-course-clean-cutover-v1"
for x in titus_u1_local_gotrue_fixture.sql shared_titus_current_person_signed_candidate.sql titus_account_context_candidate.sql \
  titus_institution_account_admission_issuer_candidate.sql \
  shared_titus_institution_manager_governance_candidate.sql \
  shared_titus_institution_root_establishment_candidate.sql \
  titus_institution_account_self_service_candidate.sql; do
  test -s "$d/$x" || exit 3
done
tmp="$(mktemp -d)"
started=false
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  if [[ "$started" == true ]]; then
    (cd "$tmp" && timeout 90s supabase stop --no-backup >/dev/null 2>&1) || true
  fi
  rm -rf -- "$tmp"
  exit "$rc"
}
trap cleanup EXIT INT TERM
cd "$tmp"
supabase init --force >/dev/null
# Disable confirmation for disposable local @example.invalid identities only.
python3 - <<'PY'
from pathlib import Path
p=Path("supabase/config.toml")
s=p.read_text()
a=s.index("[auth.email]")
b=s.find("\n[",a+1)
if b<0:b=len(s)
section=s[a:b]
import re
if re.search(r"(?m)^enable_confirmations\s*=",section):
    section=re.sub(r"(?m)^enable_confirmations\s*=\s*(?:true|false)",
                   "enable_confirmations = false",section,count=1)
else:
    section += "\nenable_confirmations = false\n"
p.write_text(s[:a]+section+s[b:])
PY
timeout 480s supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor >/dev/null
started=true
db="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
# Plain local SQL assembly; no migration receipt or live project.
# All exact candidate SQL is unchanged; one session supplies clone guards.
{
  echo "SET app.titus_u1_local_signed_fixture = 'approved';"
  printf '\\i %s/titus_u1_local_gotrue_fixture.sql\n' "$d"
  echo "SET app.shared_course_clone = 'approved';"
  printf '\\i %s/shared_titus_current_person_signed_candidate.sql\n' "$d"
  printf '\\i %s/titus_account_context_candidate.sql\n' "$d"
  printf '\\i %s/titus_institution_account_admission_issuer_candidate.sql\n' "$d"
  printf '\\i %s/shared_titus_institution_manager_governance_candidate.sql\n' "$d"
  printf '\\i %s/shared_titus_institution_root_establishment_candidate.sql\n' "$d"
  printf '\\i %s/titus_institution_account_self_service_candidate.sql\n' "$d"
  echo "NOTIFY pgrst, 'reload schema';"
} > "$tmp/held-local-setup.sql"
psql "$db" -X -v ON_ERROR_STOP=1 -q -f "$tmp/held-local-setup.sql" >/dev/null
timeout 180s python3 "$root/scripts/validate-titus-u1-gotrue-local-signed.py" \
 --db-url "$db" --output "$tmp/attestation.txt"
test -s "$tmp/attestation.txt"
grep -q 'PASS genuine local GoTrue + PostgREST U1' "$tmp/attestation.txt"
echo "PASS HELD TITUS U1 genuine locally signed test only (no production schema/release)"
