#!/usr/bin/env bash
# U1A source-only gate. No production connection, migration, or persistence.
set -euo pipefail
HERE="$(cd -- "$(dirname -- "$0")" && pwd)"
SOCKET="$HOME/atlas-local-test/private-schema"
PSQL="/Applications/Postgres.app/Contents/Versions/17/bin/psql"
[[ $# == 0 ]] || { echo 'STOP: no arguments accepted'; exit 1; }
# Source identity is a prerequisite, not a value provided by a browser.
# Refuse an untracked local replacement of SQL, tests or the runner itself.
command -v git >/dev/null || { echo 'STOP: git is required'; exit 1; }
CHECKOUT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)" ||
 { echo 'STOP: candidate is not in a reviewed Git checkout'; exit 1; }
[[ "$HERE" == "$CHECKOUT/candidates/atlas_governed_rulebook_u1a_v1" ]] ||
 { echo 'STOP: unexpected candidate source location'; exit 1; }
SOURCE_BRANCH="$(git -C "$CHECKOUT" symbolic-ref --quiet --short HEAD 2>/dev/null)" ||
 { echo 'STOP: candidate branch must be a named reviewed branch'; exit 1; }
[[ "$SOURCE_BRANCH" == "candidate/atlas-u1a-governed-rulebook-adoption-20261103" ]] ||
 { echo 'STOP: unexpected candidate branch'; exit 1; }
[[ -z "$(git -C "$CHECKOUT" status --porcelain --untracked-files=all)" ]] ||
 { echo 'STOP: working tree is dirty or contains untracked files'; exit 1; }
SOURCE_SHA="$(git -C "$CHECKOUT" rev-parse HEAD)"
[[ "$SOURCE_SHA" =~ ^[[:xdigit:]]{40}$ ]] ||
 { echo 'STOP: immutable source commit could not be resolved'; exit 1; }
echo "SOURCE_SHA=$SOURCE_SHA (held test; not a release migration)"

[[ -x "$PSQL" ]] || { echo 'STOP: local Postgres.app 17 absent'; exit 1; }
for file in candidate.sql postconditions.sql; do
 [[ -f "$HERE/$file" ]] || { echo "STOP: missing $file"; exit 1; }
 if grep -Eiq '^[[:space:]]*(COMMIT|ROLLBACK|BEGIN[[:space:];]|\\(connect|i|!|copy|gexec))' "$HERE/$file"; then
   echo "STOP: unexpected transaction or psql command in $file"; exit 1
 fi
done
[[ -f "$HERE/../../tests/atlas-u1a-governed-rulebook-source.test.mjs" ]] ||
 { echo 'STOP: source test missing'; exit 1; }
node --test "$HERE/../../tests/atlas-u1a-governed-rulebook-source.test.mjs"
if grep -Eiq '^[[:space:]]*(DROP[[:space:]]|TRUNCATE[[:space:]]|COPY[[:space:]]|INSERT[[:space:]]+INTO[[:space:]]+(atlas[.](work_items|work_requirements|care_observation_events|work_allocations)|ledger[.]))' "$HERE/candidate.sql"; then
 echo 'STOP: destructive or original Work/Need write'; exit 1
fi
# Every query uses the same exact Unix socket, database, and PG17 tools.
q() { "$PSQL" -X -At -v ON_ERROR_STOP=1 -h "$SOCKET" -p 55432 -U postgres -d noel_schema_clone -c "$1"; }
ident="$(q "SELECT current_database()||':'||current_setting('port')||':'||CASE WHEN inet_server_addr() IS NULL THEN 'local_socket' ELSE 'network' END||':'||current_setting('server_version_num')")"
[[ "$ident" == noel_schema_clone:55432:local_socket:17* ]] ||
 { echo 'STOP: not the exact isolated PG17 clone'; exit 1; }
data_dir="$(q "SELECT current_setting('data_directory')")"
[[ "$data_dir" == "$SOCKET/pg-isolated" ]] ||
 { echo 'STOP: unexpected data_directory'; exit 1; }
for rel in atlas.organizations atlas.ledgers atlas.work_requirements atlas.ledger_organization_participations atlas.work_items ledger.ledgers reality.entities auth.users auth.sessions foundry.events foundry.workspace_authority_registry_v1 atlas.subject_disclosure_decision_events_v1; do
 [[ "$(q "SELECT (to_regclass('$rel') IS NOT NULL)::text")" == true ]] ||
 { echo "STOP: missing native clone source $rel; no SQL executed"; exit 1; }
done
for sig in 'atlas.foundry_current_signed_principal_v1()' 'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)' 'atlas.current_principal_id_v1()' 'atlas.has_current_subject_disclosure_v1(uuid,uuid,text,text,uuid,text)' 'auth.uid()'; do
 [[ "$(q "SELECT (to_regprocedure('$sig') IS NOT NULL)::text")" == true ]] ||
 { echo "STOP: missing native clone function $sig"; exit 1; }
done
for rel in atlas.governed_rulebook_versions_v1 atlas.governed_rulebook_bindings_v1; do
 [[ "$(q "SELECT (to_regclass('$rel') IS NULL)::text")" == true ]] ||
 { echo "STOP: U1A table already present $rel"; exit 1; }
done
[[ "$(q "SELECT (to_regprocedure('atlas.adopt_governed_rulebook_version_self_api_v1(uuid,uuid,uuid,text,jsonb,text,text,integer,text,uuid,uuid)') IS NULL)::text")" == true ]] ||
 { echo 'STOP: candidate writer already installed'; exit 1; }
fingerprint="SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('atlas','auth','reality','ledger','foundry') AND c.relkind IN ('r','p'))::text||':'||(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('atlas','auth','reality','ledger','foundry'))::text||':'||(SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal)::text||':'||(SELECT count(*) FROM pg_policy)::text||':'||(SELECT count(*) FROM atlas.work_items)::text||':'||(SELECT count(*) FROM atlas.work_requirements)::text||':'||(SELECT count(*) FROM foundry.events)::text"
before="$(q "$fingerprint")"
(
 printf '%s\n' 'BEGIN;' "SET LOCAL statement_timeout='30s';" "SET LOCAL lock_timeout='4s';"
 cat "$HERE/candidate.sql"
 cat "$HERE/postconditions.sql"
 printf '%s\n' 'ROLLBACK;'
) | "$PSQL" -X -At -v ON_ERROR_STOP=1 -h "$SOCKET" -p 55432 -U postgres -d noel_schema_clone
after="$(q "$fingerprint")"
[[ "$before" == "$after" ]] || { echo 'FAIL: clone fingerprint changed'; exit 1; }
for rel in atlas.governed_rulebook_versions_v1 atlas.governed_rulebook_bindings_v1; do
 [[ "$(q "SELECT (to_regclass('$rel') IS NULL)::text")" == true ]] ||
 { echo "FAIL: U1A table survived rollback: $rel"; exit 1; }
done
echo 'PASS: U1A source contract, local SQL/ACL/unsigned smoke, rollback unchanged.'
echo 'HOLD: genuine signed positive/negative actors and concurrency untested.'