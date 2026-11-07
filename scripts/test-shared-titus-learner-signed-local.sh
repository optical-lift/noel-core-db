#!/usr/bin/env bash
# HELD genuine LOCAL OAuth PKCE + PostgREST proof, with fictional sources ONLY.
# No protected environment, production URL, user or source snapshot is admitted.
set -Eeuo pipefail
[[ "$(uname -s)" == Linux ]] || { echo 'Hosted Linux only' >&2;exit 2; }
for executable in docker supabase psql python3;do
 command -v "$executable" >/dev/null || { echo "Missing $executable" >&2;exit 2; }
done
root="$(cd "$(dirname "$0")/.." && pwd -P)"
lane="$root/candidates/shared-titus-learner-private-notebook-v1"
for name in signed_local_fixture.sql candidate.sql structural_postconditions.sql validate_signed_local_http.py;do
 test -s "$lane/$name" || { echo "Missing source: $name" >&2;exit 2; }
done
scratch="$(mktemp -d "${RUNNER_TEMP:-/tmp}/titus-learner-signed.XXXXXXXX")"
chmod 700 "$scratch"
cleanup(){
 rc=$?
 trap - EXIT INT TERM
 if [[ -d "$scratch/supabase" ]];then
  (cd "$scratch" && supabase stop --no-backup >/dev/null 2>&1) || true
 fi
 case "$scratch" in
  "${RUNNER_TEMP:-/tmp}"/titus-learner-signed.*)rm -rf -- "$scratch";;
  *)echo 'Unsafe scratch path; refusing cleanup' >&2;rc=3;;
 esac
 exit "$rc"
}
trap cleanup EXIT INT TERM
unset DATABASE_URL NOEL_CORE_DATABASE_URL SUPABASE_DB_URL
unset SUPABASE_ACCESS_TOKEN SUPABASE_SERVICE_ROLE_KEY SUPABASE_PROJECT_ID
cd "$scratch"
supabase init --force >/dev/null
# The pinned Supabase CLI may already generate [auth.oauth_server].
# Update its one section in place; never append a duplicate TOML table.
python3 - <<'PY'
from pathlib import Path
import re
path=Path("supabase/config.toml")
src=path.read_text()
target="[auth.oauth_server]"
settings=('enabled = true','authorization_url_path = "/oauth/consent"')
if target in src:
    before,after=src.split(target,1)
    next_section=re.search(r"(?m)^\\[[^\\n]+\\]",after)
    section=after[:next_section.start()] if next_section else after
    tail=after[next_section.start():] if next_section else ""
    section=re.sub(r"(?m)^\\s*(?:enabled|authorization_url_path|allow_dynamic_registration)\\s*=.*(?:\\n|$)","",section)
    src=before+target+"\\n"+"\\n".join(settings)+"\\n"+section+tail
else:
    src=src.rstrip()+"\\n\\n"+target+"\\n"+"\\n".join(settings)+"\\n"
path.write_text(src)
assert src.count(target)==1
PY
# Supabase CLI's own local Auth and PostgREST: no production/remote link.
supabase start -x realtime,storage-api,imgproxy >/dev/null
db_url='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
db_identity="$(psql "$db_url" -XAtq -v ON_ERROR_STOP=1 -c \
 "select current_setting('server_version_num')::integer/10000,inet_server_addr() is null,current_user;")"
[[ "$db_identity" == '17|f|postgres' || "$db_identity" == '17|t|postgres' ]] || {
 echo 'Unexpected local database fingerprint' >&2;exit 3;
}
# Port and host are pinned to local Supabase; never external DB.
[[ "$(psql "$db_url" -XAtq -v ON_ERROR_STOP=1 -c "select current_setting('port')")" == '5432' ]] || {
 echo 'Unexpected internal PostgreSQL port' >&2;exit 3;
}
psql "$db_url" -Xq -v ON_ERROR_STOP=1 -f "$lane/signed_local_fixture.sql"
psql "$db_url" -Xq -v ON_ERROR_STOP=1 -f "$lane/candidate.sql"
psql "$db_url" -Xq -v ON_ERROR_STOP=1 -f "$lane/structural_postconditions.sql"
python3 "$lane/validate_signed_local_http.py" \
 --db-url "$db_url" --output "$scratch/signed-summary.txt"
test -s "$scratch/signed-summary.txt"
grep -q '^PASS genuine LOCAL OAuth' "$scratch/signed-summary.txt"
cat "$scratch/signed-summary.txt"
echo 'PASS local signed OAuth/REST proof; independent production-shaped protected clone remains HELD.'
