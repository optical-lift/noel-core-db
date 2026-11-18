#!/usr/bin/env python3
"""U2F 06: genuine SQL behavior on a *fictional* PostgreSQL 17 database.

The fake request.jwt.claim.sub is NOT a GoTrue-signed session. No live auth,
Noel schema, private data, migrations or delegated Work are tested.
"""
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SQL = REPO / "candidates/atlas/uni_ops_u2f_universal_delegated_command_v1/06_signed_native_root_lifecycle_held.sql"
FIXTURE = HERE / "root_lifecycle_fixture.sql"

def fake(n):
    return f"00000000-0000-4000-8000-{n:012d}"

ROOT1, ROOT2 = fake(501), fake(502)
LEDGER1, LEDGER2 = fake(301), fake(302)
PERSON1, PERSON2 = fake(201), fake(202)
OWNER1, STRANGER = fake(1201), fake(1202)
EXPLICIT = "I reaffirm this exact Ledger authority"

def run(source, expected_failure=False):
    command=["psql","-X","-A","-t","-q","-v","ON_ERROR_STOP=1"]
    p=subprocess.run(command,input=source,text=True,capture_output=True,
                     cwd=REPO,check=False)
    if expected_failure:
        if p.returncode==0:
            raise AssertionError(f"expected denial but statement succeeded: {source[:250]}")
        return p.stderr
    if p.returncode:
        raise AssertionError("fictional PostgreSQL SQL failed: "+p.stderr[:1500])
    return p.stdout.strip()

def signed_sql(sql, actor=OWNER1, mutation=None, rollback=False, session_override="default"):
    chunks=["BEGIN;"]
    if actor is not None:
        chunks.append("SELECT pg_catalog.set_config('request.jwt.claim.sub','"+actor+"',true);")
        session=({"00000000-0000-4000-8000-000000001201":fake(901),
                  "00000000-0000-4000-8000-000000001202":fake(902)}.get(actor,fake(999))
                 if session_override=="default" else session_override)
        claims=json.dumps({"session_id":session} if session is not None else {})
        chunks.append("SET LOCAL request.jwt.claims = '"+claims+"';")
    if mutation:
        chunks.append(mutation)
    chunks.append(sql)
    chunks.append("ROLLBACK;" if rollback else "COMMIT;")
    return "\n".join(chunks)

def assert_denied(label, sql, actor=OWNER1, mutation=None, session_override="default"):
    diagnostic=run(signed_sql(sql,actor=actor,mutation=mutation,
                              rollback=True,session_override=session_override),True)
    if "ERROR:" not in diagnostic:
        raise AssertionError(label+": unexpected failure category "+diagnostic[:200])

def j(output, label):
    items=[json.loads(line) for line in output.splitlines()
           if line.lstrip().startswith("{")]
    if len(items)!=1:
        raise AssertionError(f"{label}: need one JSON receipt, got {output!r}")
    return items[0]

def snapshot():
    out=run("SELECT pg_catalog.jsonb_build_object("
            "'candidates',(SELECT count(*) FROM ledger.seat_responsibilities),"
            "'events',(SELECT count(*) FROM ledger.actions));")
    return j(out,"snapshot")

def candidate(root=ROOT1,ledger=LEDGER1):
    return j(run("SELECT atlas.uni_ops_u2f_root_candidate_current_held_v1("
                 f"'{root}'::uuid,'{ledger}'::uuid);"),"candidate")

def admission(root=ROOT1, ledger=LEDGER1, attestation=EXPLICIT):
    return (f"SELECT atlas.uni_ops_u2f_root_reaffirm_held_v1("
            f"'{root}'::uuid,'{ledger}'::uuid,'{attestation}');")

def revocation(record_id,reason="Human review withdraws the native root candidate"):
    return (f"SELECT atlas.uni_ops_u2f_root_revoke_held_v1("
            f"'{record_id}'::uuid,'{reason}');")

# Only fictional fixture + held functions in an empty private PG17 service.
run(f"\\i {FIXTURE.relative_to(REPO)}\n\\i {SQL.relative_to(REPO)}")

privileges=run("""
SELECT pg_catalog.jsonb_build_object(
  'authenticatedCanAdmit',
    has_function_privilege('authenticated',
      'atlas.uni_ops_u2f_root_reaffirm_held_v1(uuid,uuid,text)','EXECUTE'),
  'serviceCanAdmit',
    has_function_privilege('service_role',
      'atlas.uni_ops_u2f_root_reaffirm_held_v1(uuid,uuid,text)','EXECUTE'),
  'anonCanAdmit',
    has_function_privilege('anon',
      'atlas.uni_ops_u2f_root_reaffirm_held_v1(uuid,uuid,text)','EXECUTE'),
  'authenticatedCanRevoke',
    has_function_privilege('authenticated',
      'atlas.uni_ops_u2f_root_revoke_held_v1(uuid,text)','EXECUTE'),
  'authenticatedCanRead',
    has_function_privilege('authenticated',
      'atlas.uni_ops_u2f_root_candidate_current_held_v1(uuid,uuid)','EXECUTE')
);""")
# PostgreSQL PUBLIC is a pseudo-role, not a named role for privilege lookup;
# explicit ACL check below covers all required real application roles.
acl=j(privileges,"ACL")
for key,value in acl.items():
    if value is not False:
        raise AssertionError("unexpected application EXECUTE: "+key)

initial=snapshot()
assert initial=={"candidates":0,"events":0},initial

# A guessed native Seat/Responsibility without a genuine audit action and
# original signed reaffirmation may not become a source-effective candidate.
forged=(
 f"INSERT INTO ledger.seat_responsibilities("
 "id,seat_id,responsibility_key,responsibility_state,scope) VALUES("
 f"'{fake(700)}','{fake(601)}','ledger_governing_root_v1','active',"
 f"'{{\"sourceKind\":\"historical_root_reaffirmation_held\","
 f"\"originalRootReceiptId\":\"{ROOT1}\","
 f"\"nativeLedgerId\":\"{LEDGER1}\"}}'::jsonb);"
)
out=run(signed_sql(forged+" SELECT atlas.uni_ops_u2f_root_candidate_current_held_v1("
                    f"'{ROOT1}'::uuid,'{LEDGER1}'::uuid);",rollback=True))
values=[json.loads(line) for line in out.splitlines() if line.startswith("{")]
assert len(values)==1 and values[0]["candidateSourceCurrent"] is False

for label,statement,actor,mutation in [
 ("no current human",admission(),None,None),
 ("wrong Person",admission(),STRANGER,None),
 ("wrong Ledger",admission(ROOT1,LEDGER2),OWNER1,None),
 ("wrong original receipt",admission(fake(999),LEDGER1),OWNER1,None),
 ("no explicit attestation",admission(attestation="Yes"),OWNER1,None),
 ("historical authority ended",admission(),OWNER1,
  f"UPDATE atlas.principal_ledger_authorities SET status='ended',ended_at=now() WHERE id='{ROOT1}';"),
 ("native Ledger paused",admission(),OWNER1,
  f"UPDATE ledger.ledgers SET ledger_state='paused' WHERE id='{LEDGER1}';"),
 ("legacy Ledger retired",admission(),OWNER1,
  f"UPDATE atlas.ledgers SET status='retired' WHERE id='{LEDGER1}';"),
 ("native Seat wrong Person",admission(),OWNER1,
  f"UPDATE ledger.seats SET person_entity_id='{PERSON2}' WHERE id='{fake(601)}';"),
 ("native Seat ended",admission(),OWNER1,
  f"UPDATE ledger.seats SET seat_state='ended',ended_at=now() WHERE id='{fake(601)}';"),
 ("native Seat future",admission(),OWNER1,
  f"UPDATE ledger.seats SET began_at=now()+interval '1 day' WHERE id='{fake(601)}';"),
 ("inactive Principal",admission(),OWNER1,
  f"UPDATE atlas.principals SET status='inactive' WHERE id='{fake(101)}';"),
]:
    assert_denied(label,statement,actor,mutation)
# Real schema supports session_id -> auth.sessions; this is still fake JWT.
assert_denied("missing JWT session claim",admission(),session_override=None)
assert_denied("unknown JWT session",admission(),session_override=fake(999))
assert_denied("wrong-user JWT session",admission(),session_override=fake(902))
assert_denied("malformed JWT session",admission(),session_override="not-a-uuid")
assert_denied("deleted session",admission(),mutation=(
    f"DELETE FROM auth.sessions WHERE id='{fake(901)}';"))
assert_denied("expired session",admission(),mutation=(
    f"UPDATE auth.sessions SET not_after=now()-interval '1 minute' WHERE id='{fake(901)}';"))

assert snapshot()==initial,"Denied admits changed persisted rows"

receipt1=j(run(signed_sql(admission())),"native ledger 1 admission")
assert receipt1["candidateRecorded"] is True
assert receipt1["independentSourceAdjudication"] is False
assert receipt1["governingRootVerified"] is False
assert receipt1["delegatedWorkAuthorized"] is False
id1=receipt1["nativeResponsibilityId"]
assert candidate()["candidateSourceCurrent"] is True
assert candidate()["delegatedWorkAuthorized"] is False
assert snapshot()=={"candidates":1,"events":1}
assert_denied("repeated admission is not new authority",admission())

# Same real Person + same institution Entity; independent Ledger, separate
# signed action and separate one-time native responsibility. No inheritance.
receipt2=j(run(signed_sql(admission(ROOT2,LEDGER2))),"native ledger 2 admission")
assert receipt2["candidateRecorded"] is True
id2=receipt2["nativeResponsibilityId"]
assert id1!=id2
assert candidate(ROOT2,LEDGER2)["candidateSourceCurrent"] is True
assert snapshot()=={"candidates":2,"events":2}

assert_denied("outsider cannot revoke",revocation(id1),STRANGER)
assert_denied("empty reason cannot revoke",revocation(id1,"No"))
assert_denied("wrong historical candidate",revocation(fake(999)))
assert_denied("revocation requires current session",revocation(id1),
              session_override=fake(902))
assert_denied("revocation denies expired session",revocation(id1),mutation=(
    f"UPDATE auth.sessions SET not_after=now()-interval '1 minute' WHERE id='{fake(901)}';"))

assert candidate()["candidateSourceCurrent"] is True

revoke1=j(run(signed_sql(revocation(id1))),"root 1 revocation")
assert revoke1["revoked"] is True and revoke1["replayed"] is False
assert revoke1["delegatedWorkAuthorized"] is False
assert candidate()["candidateSourceCurrent"] is False
assert candidate(ROOT2,LEDGER2)["candidateSourceCurrent"] is True
assert snapshot()=={"candidates":2,"events":3}
replay=j(run(signed_sql(revocation(id1))),"revocation replay")
assert replay["revoked"] is True and replay["replayed"] is True
assert snapshot()=={"candidates":2,"events":3},"Replay created audit event"
assert_denied("revoked root may not be regranted with same seat/key",admission())

# Even an active responsibility is never a final authorization. Current
# source, Person and native Seat must remain current at evaluation time.
affected=run(signed_sql(
 f"UPDATE atlas.principal_ledger_authorities SET status='ended',ended_at=now() "
 f"WHERE id='{ROOT2}'; "
 f"SELECT atlas.uni_ops_u2f_root_candidate_current_held_v1('{ROOT2}','{LEDGER2}');",
 rollback=True))
assert j(affected,"source ended")["candidateSourceCurrent"] is False
affected=run(signed_sql(
 f"UPDATE ledger.seats SET seat_state='ended',ended_at=now() WHERE id='{fake(602)}';"
 f" SELECT atlas.uni_ops_u2f_root_candidate_current_held_v1('{ROOT2}','{LEDGER2}');",
 rollback=True))
assert j(affected,"seat ended")["candidateSourceCurrent"] is False
assert candidate(ROOT2,LEDGER2)["candidateSourceCurrent"] is True
assert run("SELECT (to_regclass('atlas.work_items') IS NULL AND "
           "to_regclass('atlas.tasks') IS NULL)::text;")=="true", "Work/Task store appeared"
print("U2F_06_SYNTHETIC_SIGNED_SHAPE_AND_NATIVE_REVOCATION=PASS")
print("AUTHENTIC_GOTRUE_SIGNED_ACTOR=NOT_TESTED")
print("INDEPENDENT_SOURCE_ADJUDICATION=NO")
print("DELEGATED_WORK_COMMAND_ACTIVE=NO")
print("PRODUCTION_MUTATION=NONE")
