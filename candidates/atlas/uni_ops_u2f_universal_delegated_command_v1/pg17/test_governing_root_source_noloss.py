#!/usr/bin/env python3
"""U2F 04: fictional PostgreSQL no-loss/root-authority negative checks only."""
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PREFLIGHT = ROOT / "candidates/atlas/uni_ops_u2f_universal_delegated_command_v1/04_governing_root_source_noloss_preflight_held.psql"
FIXTURE = HERE / "governing_root_fixture.sql"
ROOT_ID = "11111111-1111-4111-8111-111111111111"
LEDGER_ID = "44444444-4444-4444-8444-444444444444"
OTHER_ID = "88888888-8888-4888-8888-888888888888"

def psql(source, from_file=False):
    cmd = ["psql", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1"]
    if from_file:
        cmd.extend(["-f", str(source)])
        input_data = None
    else:
        input_data = source
    run = subprocess.run(cmd, input=input_data, text=True,
                         capture_output=True, cwd=ROOT, check=False)
    if run.returncode:
        raise AssertionError(f"isolated psql error: {run.stderr.strip()}")
    return run.stdout

def probe(case, mutation="", root=ROOT_ID, ledger=LEDGER_ID):
    script = (
        "BEGIN;\n"
        + (mutation + "\n" if mutation else "")
        + f"\\set governing_root_receipt_id {root}\n"
        + f"\\set native_ledger_id {ledger}\n"
        + f"\\i {PREFLIGHT.relative_to(ROOT)}\n"
        + "ROLLBACK;\n"
    )
    output = psql(script)
    objects = [json.loads(line) for line in output.splitlines()
               if line.lstrip().startswith("{")]
    if len(objects) != 1:
        raise AssertionError(f"{case}: expected exactly one nonidentity JSON receipt; got {output!r}")
    data = objects[0]
    for flag in ("nativeGoverningRootVerified", "sourceAdjudicationComplete",
                 "workIssuerAuthorized", "originalWorkCreated",
                 "legacyRootRetirementAuthorized", "productionMutation"):
        if data.get(flag) is not False:
            raise AssertionError(f"{case}: unexpectedly authorized {flag}")
    if data.get("sourceOnly") is not True:
        raise AssertionError(f"{case}: source-only marker missing")
    if any(value in output for value in (ROOT_ID, LEDGER_ID, OTHER_ID)):
        raise AssertionError(f"{case}: private source ID leaked in receipt")
    return data

def check(condition, description):
    if not condition:
        raise AssertionError(description)

psql(FIXTURE, from_file=True)
baseline = probe("exact original plus native identity")
for field in ("sourceOriginalReceiptMatched",
              "sourceOriginalGoverningDecisionCurrent",
              "nativeLedgerSameIdentityCurrent", "nativePersonSeatAligned",
              "seatProvenanceNamesExactOriginalReceipt",
              "entityResponsibilityCandidateObserved"):
    check(baseline.get(field) is True, f"baseline missed {field}")

cases = [
    ("unknown original receipt", "", OTHER_ID, LEDGER_ID,
     "sourceOriginalReceiptMatched"),
    ("wrong Ledger scope", "", ROOT_ID, OTHER_ID, "sourceOriginalReceiptMatched"),
    ("ended original authority", "UPDATE atlas.principal_ledger_authorities SET status='ended', ended_at=now();", ROOT_ID, LEDGER_ID,
     "sourceOriginalGoverningDecisionCurrent"),
    ("wrong original authority kind", "UPDATE atlas.principal_ledger_authorities SET authority_kind='mere_seat';", ROOT_ID, LEDGER_ID,
     "sourceOriginalGoverningDecisionCurrent"),
    ("retired old Ledger", "UPDATE atlas.ledgers SET status='retired';", ROOT_ID, LEDGER_ID,
     "sourceOriginalGoverningDecisionCurrent"),
    ("inactive Principal", "UPDATE atlas.principals SET status='inactive';", ROOT_ID, LEDGER_ID,
     "sourceOriginalGoverningDecisionCurrent"),
    ("missing Principal Person", "UPDATE atlas.principals SET person_id=NULL;", ROOT_ID, LEDGER_ID,
     "nativePersonSeatAligned"),
    ("retired native Ledger", "UPDATE ledger.ledgers SET ledger_state='retired', retired_at=now();", ROOT_ID, LEDGER_ID,
     "nativeLedgerSameIdentityCurrent"),
    ("ended native Seat", "UPDATE ledger.seats SET seat_state='ended', ended_at=now();", ROOT_ID, LEDGER_ID,
     "nativePersonSeatAligned"),
    ("future native Seat", "UPDATE ledger.seats SET began_at=now()+interval '1 day';", ROOT_ID, LEDGER_ID,
     "nativePersonSeatAligned"),
    ("wrong Person on Seat", f"UPDATE ledger.seats SET person_entity_id='{OTHER_ID}';", ROOT_ID, LEDGER_ID,
     "nativePersonSeatAligned"),
    ("no original receipt provenance", "UPDATE ledger.seats SET seat_basis='{}'::jsonb;", ROOT_ID, LEDGER_ID,
     "seatProvenanceNamesExactOriginalReceipt"),
    ("forged other receipt provenance", f"UPDATE ledger.seats SET seat_basis=jsonb_build_object('legacyLedgerAuthorityEvidenceId','{OTHER_ID}');", ROOT_ID, LEDGER_ID,
     "seatProvenanceNamesExactOriginalReceipt"),
    ("entity responsibility absent", "DELETE FROM reality.responsibility_relations;", ROOT_ID, LEDGER_ID,
     "entityResponsibilityCandidateObserved"),
    ("entity responsibility inactive", "UPDATE reality.responsibility_relations SET relation_state='ended', ended_at=now();", ROOT_ID, LEDGER_ID,
     "entityResponsibilityCandidateObserved"),
    ("entity responsibility wrong subject", f"UPDATE reality.responsibility_relations SET jurisdiction_entity_id='{OTHER_ID}';", ROOT_ID, LEDGER_ID,
     "entityResponsibilityCandidateObserved"),
]
for name, mutation, receipt, ledger, expected_false in cases:
    data = probe(name, mutation, receipt, ledger)
    check(data[expected_false] is False, f"{name}: unexpectedly passed {expected_false}")

check(probe("after rolled-back negatives") == baseline, "fixture drift after rollback")
table_check = psql("SELECT (to_regclass('atlas.work_items') IS NULL AND to_regclass('atlas.tasks') IS NULL)::text;")
check("true" in table_check.splitlines(), "synthetic Work or Task engine appeared")
print(f"U2F_GOVERNING_ROOT_NOSS_PG17_SYNTHETIC=PASS cases={len(cases)+2}")
print("NATIVE_GOVERNING_ROOT_PROVEN=NO")
print("EXECUTABLE_WORK_ISSUER=NO")
print("PRODUCTION_MUTATION=NONE")
