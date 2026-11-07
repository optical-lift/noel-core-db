#!/usr/bin/env bash
# Held, disposable CLI packaging rehearsal only. No remote DB connection.
set -Eeuo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source="$repo/candidates/shared-titus-learner-private-notebook-v1/candidate.sql"
[[ -s "$source" ]] || exit 2
command -v supabase >/dev/null || exit 2
expected='d1a00f02b8673e8b016ab8ef124a52dbe40c8101'
[[ "$(git -C "$repo" hash-object "$source")" == "$expected" ]] || {
  echo 'Held SQL no longer matches reviewed blob' >&2; exit 3;
}
root="${RUNNER_TEMP:-/tmp}"
scratch="$(mktemp -d "$root/titus-learner-held-package.XXXXXXXX")"
chmod 700 "$scratch"
cleanup(){
  rc=$?
  trap - EXIT INT TERM
  case "$scratch" in
    "$root"/titus-learner-held-package.*) rm -rf -- "$scratch";;
    *) echo 'Unsafe scratch path' >&2; rc=3;;
  esac
  exit "$rc"
}
trap cleanup EXIT INT TERM
unset DATABASE_URL NOEL_CORE_DATABASE_URL SUPABASE_DB_URL SUPABASE_ACCESS_TOKEN
unset SUPABASE_PROJECT_ID SUPABASE_SERVICE_ROLE_KEY
cd "$scratch"
supabase init --force >/dev/null
supabase migration new shared_titus_learner_private_notebook_clone_only_v1 >/dev/null
mapfile -t generated < <(find "$scratch/supabase/migrations" -maxdepth 1 -type f \
  -name '*_shared_titus_learner_private_notebook_clone_only_v1.sql' -print)
[[ "${#generated[@]}" == 1 ]] || exit 3
[[ "$(basename "${generated[0]}")" =~ ^[0-9]{14}_shared_titus_learner_private_notebook_clone_only_v1[.]sql$ ]] || exit 3
cp -- "$source" "${generated[0]}"
cmp -s "$source" "${generated[0]}" || exit 3
[[ "$(git -C "$repo" hash-object "${generated[0]}")" == "$expected" ]] || exit 3
[[ ! -e "$repo/supabase/migrations/$(basename "${generated[0]}")" ]] || exit 3
printf '%s\n' 'PASS: one scratch shared_ package with exact source bytes; no repo migration, database or protected access.'
