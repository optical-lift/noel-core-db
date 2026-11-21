#!/usr/bin/env python3
"""Disposable PG17 test: keep five original decisions distinct and nonexecutable."""
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FIXTURE = HERE / "native_root_custody_fixture.sql"
PLAN = ROOT / "candidates/atlas/uni_ops_u2f_universal_delegated_command_v1/05_native_ledger_root_custody_candidate_held.psql"
def fake_id(n):
    return f"00000000-0000-4000-8000-{n:012d}"

def sql(command, fixture=False):
    call = ["psql","-X","-A","-t","-q","-v","ON_ERROR_STOP=1"]
    if fixture:
        call += ["-f",str(command)]
        incoming=None
    else:
        incoming=command
    result=subprocess.run(call,input=incoming,text=True,capture_output=True,cwd=ROOT,check=False)
    if result.returncode:
        raise AssertionError(f"isolated PostgreSQL failed: {result.stderr.strip()}")
    return result.stdout

def inspect(case, mutation=""):
    query=(
      "BEGIN;\n"+(mutation+"\n" if mutation else "")
      +f"\\i {PLAN.relative_to(ROOT)}\nROLLBACK;\n"
    )
    output=sql(query)
    receipts=[json.loads(line) for line in output.splitlines() if line.strip().startswith("{")]
    if len(receipts)!=1:
        raise AssertionError(f"{case}: expected one aggregate-only receipt; output={output!r}")
    item=receipts[0]
    for key in ("newRootAuthorityEstablished","fiveOriginalDecisionsAdjudicated",
                "candidateCanEstablishGoverningAuthorityWithoutAdjudication",
                "canRetireOriginalRootTable","canIssueWork","productionMutation"):
        if item.get(key) is not False:
            raise AssertionError(f"{case}: unauthorized flag {key}")
    if item.get("sourceOnly") is not True:
        raise AssertionError(f"{case}: source-only marker absent")
    if any(fake_id(n) in output for n in range(100,607)):
        raise AssertionError(f"{case}: fake identity escaped aggregation")
    return item

def expect(receipt, key, expected, case):
    if receipt.get(key)!=expected:
        raise AssertionError(f"{case}: {key} expected {expected}, got {receipt.get(key)}")

sql(FIXTURE,fixture=True)
base=inspect("five-root baseline")
for key,value in (
 ("allHistoricalOriginalRootReceipts",6),
 ("currentOriginalRootReceipts",5),
 ("historicalNoncurrentOriginalRootReceipts",1),
 ("exactNativeSeatCandidates",5),
 ("missingOrAmbiguousNativeSeatCandidates",0),
 ("exactHistoricalSeatCitations",3),
 ("rootsWithoutExactHistoricalSeatCitation",2),
 ("personSubjectPairsWithMultipleLedgers",1),
 ("rootsSharingPersonAndInstitutionAcrossLedgers",2),
 ("existingActiveNativeRootResponsibilityMatches",0),
 ("rootsWithNoExactNativeRootResponsibility",5),
 ("candidateCarriesExactLedgerScope",True),
 ("candidateCarrier","ledger.seat_responsibilities"),
):
    expect(base,key,value,"five-root baseline")
cases=[
 ("ended original still historical",
  f"UPDATE atlas.principal_ledger_authorities SET status='ended',ended_at=now() WHERE id='{fake_id(505)}';",
  "currentOriginalRootReceipts",4),
 ("missing native seat",
  f"DELETE FROM ledger.seats WHERE id='{fake_id(605)}';",
  "exactNativeSeatCandidates",4),
 ("wrong Person on native seat",
  f"UPDATE ledger.seats SET person_entity_id='{fake_id(201)}' WHERE id='{fake_id(605)}';",
  "exactNativeSeatCandidates",4),
 ("paused native Ledger",
  f"UPDATE ledger.ledgers SET ledger_state='paused' WHERE id='{fake_id(305)}';",
  "exactNativeSeatCandidates",4),
 ("retired old Ledger",
  f"UPDATE atlas.ledgers SET status='retired' WHERE id='{fake_id(305)}';",
  "exactNativeSeatCandidates",4),
 ("inactive Principal",
  f"UPDATE atlas.principals SET status='inactive' WHERE id='{fake_id(104)}';",
  "exactNativeSeatCandidates",4),
 ("future native seat",
  f"UPDATE ledger.seats SET began_at=now()+interval '2 days' WHERE id='{fake_id(605)}';",
  "exactNativeSeatCandidates",4),
 ("ended native seat",
  f"UPDATE ledger.seats SET seat_state='ended',ended_at=now() WHERE id='{fake_id(605)}';",
  "exactNativeSeatCandidates",4),
 ("no original seat citation",
  "UPDATE ledger.seats SET seat_basis='{}'::jsonb;",
  "exactHistoricalSeatCitations",0),
 ("false original seat citation",
  f"UPDATE ledger.seats SET seat_basis=jsonb_build_object('legacyLedgerAuthorityEvidenceId','{fake_id(506)}');",
  "exactHistoricalSeatCitations",0),
 ("same subject collision kept separate",
  f"UPDATE ledger.ledgers SET subject_entity_id='{fake_id(499)}' WHERE id='{fake_id(302)}';",
  "personSubjectPairsWithMultipleLedgers",0),
 ("forged native root responsibility cannot authorize issuance",
  f"INSERT INTO ledger.seat_responsibilities VALUES ('{fake_id(701)}','{fake_id(605)}','ledger_governing_root_v1','active');",
  "existingActiveNativeRootResponsibilityMatches",1),
]
for name,mutation,key,expected in cases:
    state=inspect(name,mutation)
    expect(state,key,expected,name)
expect(inspect("recovery after rollback"),"exactNativeSeatCandidates",5,"rollback")
if inspect("recovery after rollback")!=base:
    raise AssertionError("synthetic root/seat state drifted after negative transactions")
assert "true" in sql("SELECT (to_regclass('atlas.work_items') IS NULL AND to_regclass('atlas.tasks') IS NULL)::text;").splitlines()
print(f"U2F_NATIVE_ROOT_CUSTODY_PG17_SYNTHETIC=PASS negative_cases={len(cases)}")
print("AUTHORITY_CUTOVER_ADJUDICATED=NO")
print("CAN_ISSUE_WORK=NO")
print("PRODUCTION_MUTATION=NONE")
