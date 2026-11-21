#!/usr/bin/env python3
"""Held U2F/P0: one nonmutating migration preflight, disposable PG17 fake rows."""
import json
import os
from pathlib import Path
import subprocess

FOLDER=Path(__file__).resolve().parents[1]
FIXTURE=FOLDER/"pg17"/"legacy_ledger_migration_fixture.sql"
SOURCE=FOLDER/"03_legacy_ledger_retirement_readonly_preflight_held.psql"
LEGACY="11111111-1111-4111-8111-111111111111"
CASE="66666666-6666-4666-8666-666666666666"
ENTITY="77777777-7777-4777-8777-777777777777"
OTHER="88888888-8888-4888-8888-888888888888"
SEAT="99999999-9999-4999-8999-999999999999"
PERSON="44444444-4444-4444-8444-444444444444"

def invoke(*args,expected_ok=True):
    p=subprocess.run(
        ["psql","-X","-q","-v","ON_ERROR_STOP=1",*args],
        capture_output=True,text=True,env=os.environ
    )
    if expected_ok and p.returncode!=0:
        raise AssertionError(f"synthetic psql failed: {p.stderr[-1300:]}")
    if not expected_ok and p.returncode==0:
        raise AssertionError("source accepted a missing scoped legacy Ledger identity")
    return p

def exec_synthetic(sql):
    invoke("-c",sql)

def receipt(target=LEGACY):
    p=invoke("-A","-t","-v",f"legacy_ledger_id={target}","-f",str(SOURCE))
    rows=[line.strip() for line in p.stdout.splitlines() if line.lstrip().startswith("{")]
    if len(rows)!=1:
        raise AssertionError(f"expected one safe aggregate report: {p.stdout[-900:]}")
    data=json.loads(rows[0])
    for flag in ("canActivateLedger","workIssuerAuthorized","originalWorkCreated",
                 "legacyTableDropAuthorized","productionMutation"):
        assert data[flag] is False,(flag,data)
    assert data["contractVersion"]=="uni_ops_u2f_legacy_to_native_ledger_readonly_preflight_v1"
    assert not any(uuid in json.dumps(data) for uuid in (LEGACY,CASE,ENTITY,PERSON,OTHER)), "identity disclosed"
    return data

def assert_next(expected):
    r=receipt()
    assert r["nextReview"]==expected,(expected,r)
    return r

invoke("-f",str(FIXTURE))
invoke("-f",str(SOURCE),expected_ok=False) # No hidden or implicit target selection.

r=assert_next("native_legacy_migration_onboarding_not_admitted")
assert r["activeGoverningInstitutionCount"]==1 and r["activeRootCount"]==1
assert r["nativeAdjudicationCaseCount"]==0
assert r["sourceReadyForSeparateActivationReview"] is False
assert receipt(OTHER)["nextReview"]=="legacy_source_unavailable"

exec_synthetic(f"""
 INSERT INTO reality.entities VALUES ('{ENTITY}','institution','canonical');
 INSERT INTO ledger.onboarding_cases VALUES (
   '{CASE}','legacy_adjudicated_migration',
   '{{"legacyLedgerId":"{LEGACY}","migrationAdjudicated":false}}'::jsonb,
   'in_progress','{ENTITY}');
""")
r=assert_next("canonical_institution_or_onboarding_not_ready")
assert r["readyCanonicalInstitutionCaseCount"]==0

exec_synthetic(f"""
 UPDATE ledger.onboarding_cases
 SET onboarding_basis='{{"legacyLedgerId":"{LEGACY}","migrationAdjudicated":true}}'::jsonb,
 onboarding_state='ready_to_activate' WHERE id='{CASE}';
""")
r=assert_next("owner_review_native_ledger_activation")
assert r["sourceReadyForSeparateActivationReview"] is True
assert r["nativeActiveSameIdentity"] is False

exec_synthetic(f"""
 INSERT INTO ledger.ledgers VALUES ('{LEGACY}','active',NULL,'{CASE}');
""")
r=assert_next("governing_person_native_seat_parity_unproven")
assert r["nativeActiveSameIdentity"] is True

exec_synthetic(f"""
 INSERT INTO ledger.seats VALUES (
 '{SEAT}','{LEGACY}','{PERSON}','active',now()-interval '1 day',NULL);
""")
r=assert_next("native_identity_parity_source_review")
assert r["nativeRootPersonSeatParityProved"] is True
assert r["sourceReadyForSeparateActivationReview"] is False

exec_synthetic(f"UPDATE ledger.seats SET person_entity_id='{OTHER}' WHERE id='{SEAT}'")
assert_next("governing_person_native_seat_parity_unproven")
exec_synthetic(f"UPDATE ledger.seats SET person_entity_id='{PERSON}' WHERE id='{SEAT}'")

exec_synthetic(f"INSERT INTO ledger.ledgers VALUES ('{OTHER}','active',NULL,'{CASE}')")
r=assert_next("native_identity_collision_halt")
assert r["nativeIdentityConflict"] is True
exec_synthetic(f"DELETE FROM ledger.ledgers WHERE id='{OTHER}'")

exec_synthetic(f"""
 INSERT INTO ledger.onboarding_cases VALUES (
 '{OTHER}','legacy_adjudicated_migration',
 '{{"legacyLedgerId":"{LEGACY}","migrationAdjudicated":true}}'::jsonb,
 'ready_to_activate','{ENTITY}');
""")
assert_next("native_onboarding_case_ambiguous")
exec_synthetic(f"DELETE FROM ledger.onboarding_cases WHERE id='{OTHER}'")

exec_synthetic("UPDATE atlas.organizations SET status='inactive'")
assert_next("institutional_governance_unresolved")
exec_synthetic("UPDATE atlas.organizations SET status='active'")

exec_synthetic("UPDATE atlas.principal_ledger_authorities SET status='revoked'")
assert_next("governing_root_custody_unresolved")
exec_synthetic("UPDATE atlas.principal_ledger_authorities SET status='active'")

r=assert_next("native_identity_parity_source_review")
assert r["legacyTableDropAuthorized"] is False
print("U2F_P0_LEGACY_LEDGER_MIGRATION_PG17_SYNTHETIC=PASS")
print("PROTECTED_CURRENT_SCHEMA_SIGNED_TEST=NOT_RUN")
print("NATIVE_LEDGER_ACTIVATION=NOT_AUTHORIZED")
print("PRODUCTION_MUTATION=NONE")
