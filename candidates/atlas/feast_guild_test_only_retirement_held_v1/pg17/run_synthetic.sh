#!/usr/bin/env bash
# Run ONLY on a disposable local PostgreSQL 17 test service (not Supabase).
set -euo pipefail
: "${PGHOST:?set PGHOST for a disposable postgres service}"
: "${PGPORT:?set PGPORT for disposable postgres service}"
: "${PGUSER:?set PGUSER for disposable postgres service}"
ROOT="candidates/atlas/feast_guild_test_only_retirement_held_v1"
fixture="$ROOT/pg17/fixture.sql"
retire="$ROOT/retire_held.sql"
check_count() {
  local db="$1" sql="$2" expected="$3"
  local actual
  actual="$(psql -X -tA -v ON_ERROR_STOP=1 -d "$db" -c "$sql")"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected aggregate $expected, got $actual in $db" >&2; exit 1
  fi
}
run_case() {
  local name="$1" mutation="$2" should_succeed="$3"
  local db="feast_guild_synth_${name}"
  createdb "$db"
  psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$fixture"
  if [[ "$mutation" != "none" ]]; then
    psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c "$mutation"
  fi
  if psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$retire" >"/tmp/${db}.log" 2>&1; then
    if [[ "$should_succeed" != "yes" ]]; then echo "FAIL: $name wrongly deleted guarded test institution" >&2; exit 1; fi
    check_count "$db" "select count(*) from atlas.organizations" 1
    check_count "$db" "select count(*) from atlas.ledgers" 1
    check_count "$db" "select count(*) from atlas.principal_ledger_authorities" 1
    check_count "$db" "select count(*) from atlas.ledger_organization_participations" 1
    check_count "$db" "select count(*) from atlas.organizations where stable_key='elm_farm'" 1
    check_count "$db" "select count(*) from atlas.ledgers where stable_key='elm_farm'" 1
    check_count "$db" "select count(*) from atlas.organizations where stable_key='feast_guild'" 0
  else
    if [[ "$should_succeed" == "yes" ]]; then echo "FAIL: positive source rejected" >&2; cat "/tmp/${db}.log"; exit 1; fi
    check_count "$db" "select count(*) from atlas.organizations" 2
    check_count "$db" "select count(*) from atlas.ledgers" 2
    check_count "$db" "select count(*) from atlas.principal_ledger_authorities" 2
    check_count "$db" "select count(*) from atlas.ledger_organization_participations" 2
  fi
  echo "PASS: $name ($should_succeed)"
}
run_case positive none yes
run_case foreign_key_block \
  "INSERT INTO atlas.farms VALUES ('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001')" no
run_case unguarded_uuid_block \
  "INSERT INTO atlas.nonfk_seat_probe VALUES ('50000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001')" no
run_case source_identity_mismatch \
  "UPDATE atlas.organizations SET metadata='{}'::jsonb WHERE stable_key='feast_guild'" no
run_case native_ledger_block \
  "INSERT INTO ledger.ledgers VALUES ('20000000-0000-4000-8000-000000000001')" no
run_case native_case_block \
  "INSERT INTO ledger.onboarding_cases VALUES ('{\"legacyLedgerId\":\"20000000-0000-4000-8000-000000000001\"}'::jsonb)" no
run_case other_organization_join \
  "INSERT INTO atlas.ledger_organization_participations VALUES ('30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','operating',false,'active',null)" no
run_case text_reference \
  "INSERT INTO atlas.organization_ledger_subjects VALUES ('10000000-0000-4000-8000-000000000001')" no
echo "Eight synthetic PG17 cases complete. No real identities or hosted database used."
