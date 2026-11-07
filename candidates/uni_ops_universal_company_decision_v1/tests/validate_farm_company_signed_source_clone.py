#!/usr/bin/env python3
"""HELD UNI-OPS signed Farm -> ONE Company decision proof; disposable LOCAL only.

Runs ONLY after independently checked PostgreSQL 17 production-shaped schema,
the exact nine held SQL sources, and a source-verified fictional Farm fixture.
Uses genuine local GoTrue credentials/session rows for each actor; invokes
UNGRANTED private source functions through privileged disposable-clone psql
with those verified claims. This is NOT public REST grant/actor-path acceptance,
not a production command, and not a migration or Work issuer.
"""
import argparse
import importlib.util
import json
import re
import subprocess
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "scripts" / "validate-atlas-work-prerequisite-signed-http.py"
SPEC = importlib.util.spec_from_file_location("uni_ops_existing_signed_local", HELPER)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("STOP: canonical signed clone helper unavailable")
base = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(base)
c1 = base.c1

SQL_FUNCS = {
    "disclose": "atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1",
    "admit": "atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1",
    "decide": "atlas.uni_ops_farm_governor_decide_current_company_case_held_v1",
    "receipt": "atlas.uni_ops_company_governed_case_receipt_self_held_v1",
}
REST_FUNCS = tuple(x.rsplit(".", 1)[1] for x in SQL_FUNCS.values())


def check(value, reason):
    if not value:
        raise AssertionError(reason)


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def identifier(value):
    return str(uuid.UUID(str(value)))


def sql(db_url, query):
    return c1.sql(db_url, query)


def scalar_uuid(obj, key):
    check(key in obj, "Fixture lacks required immutable source key: " + key)
    return identifier(obj[key])


def session_checked(db_url, access_token, expected_user=None):
    # A decoded JWT is never authorization by itself. The identity MUST have
    # genuinely signed into the local GoTrue and hold its own active DB session.
    claims = c1.jwt_payload(access_token)
    uid = identifier(claims.get("sub"))
    sid = identifier(claims.get("session_id"))
    check(claims.get("role") == "authenticated",
          "Local GoTrue signer did not receive authenticated role")
    if expected_user is not None:
        check(uid == expected_user, "Signed user and fictional fixture differ")
    check(sql(db_url, "SELECT count(*) FROM auth.sessions WHERE "
              "id=" + literal(sid) + "::uuid AND user_id="
              + literal(uid) + "::uuid") == "1",
          "Genuine local GoTrue session missing or withdrawn")
    return claims


class SourceSQLDenial(Exception):
    """Only a fixed SQLSTATE is carried out of the protected clone."""

    def __init__(self, code):
        self.code = code
        super().__init__("Private source denied with allowlisted SQLSTATE")


def private_signed(db_url, token, method, arguments, *, want_error=None):
    # This wrapper is a PRIVILEGED LOCAL SOURCE PROBE, not a public client RPC.
    # psql never gets a production URL. The claims originate exclusively from
    # local GoTrue sign-in, and the exact DB session is checked before the call.
    claims = session_checked(db_url, token)
    uid = identifier(claims["sub"])
    call = SQL_FUNCS[method] + "(" + ",".join(arguments) + ")"
    statement = (
        "BEGIN;\n"
        "SELECT set_config('request.jwt.claims',"
        + literal(json.dumps(claims, separators=(",", ":"))) + ",true);\n"
        "SELECT set_config('request.jwt.claim.sub'," + literal(uid) + ",true);\n"
        "SELECT (" + call + ")::text;\nCOMMIT;\n"
    )
    result = subprocess.run(
        ["psql", db_url, "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1",
         "-v", "VERBOSITY=verbose", "-c", statement],
        capture_output=True, text=True, check=False, timeout=35
    )
    state = next((x for x in ("42501", "23505")
                  if re.search(r"\b" + x + r"\b", result.stderr)), None)
    if want_error:
        check(result.returncode != 0 and state == want_error,
              "Expected private source SQLSTATE " + want_error
              + " was not returned")
        return None
    if result.returncode != 0 and state is not None:
        raise SourceSQLDenial(state)
    check(result.returncode == 0, "Private source operation failed; "
          "diagnose in protected clone, without printing sensitive SQL")
    payloads = [x.strip() for x in result.stdout.splitlines()
                if x.lstrip().startswith("{")]
    check(bool(payloads), "Private source returned no structured receipt")
    data = json.loads(payloads[-1])
    check(data.get("ok") is True, "Private source did not accept operation")
    return data


def count(db_url, table):
    check(table in (
        "atlas.work_items",
        "atlas.uni_ops_governed_source_cases_v1",
        "atlas.uni_ops_governed_case_decision_events_v1",
        "atlas.subject_disclosure_decision_events_v1",
        "atlas.uni_ops_farm_company_source_links_v1",
    ), "Unapproved count table")
    return int(sql(db_url, "SELECT count(*) FROM " + table))


def run(db_url, manifest_path, output):
    check(bool(re.fullmatch(
        r"postgres(?:ql)?://[^@\s]+@127[.]0[.]0[.]1:[0-9]+/postgres",
        db_url)), "STOP: signed source test accepts disposable loopback PG only")
    check(Path(manifest_path).is_file(), "Source fixture manifest absent")
    fixture = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
    check(fixture.get("kind") == "uni_ops_farm_company_source_test_only_v1",
          "Explicit source-only fictional fixture kind required")
    org = scalar_uuid(fixture, "organizationId")
    ledger = scalar_uuid(fixture, "governingLedgerId")
    farm = scalar_uuid(fixture, "farmId")
    attention = scalar_uuid(fixture, "attentionJournalId")
    subject = scalar_uuid(fixture, "nativeSubjectId")
    owner_person = scalar_uuid(fixture, "governorPersonId")
    check(owner_person == base.ROOT_PERSON, "Do not substitute a fake root")
    check(sql(db_url, "SELECT current_setting('server_version_num')::integer/10000") == "17",
          "Refuse non-PG17 database")
    # The verified client URL is loopback. The database lives inside an
    # isolated Docker network, so inet_server_addr() can be a bridge IP.
    check(sql(db_url, "SELECT count(*) FROM atlas.journal_event_index WHERE "
              "id=" + literal(attention) + "::uuid AND farm_id="
              + literal(farm) + "::uuid AND source_id="
              + literal(subject) + "::uuid") == "1",
          "Native first-party source evidence does not match fixture")
    check(count(db_url, "atlas.uni_ops_governed_source_cases_v1") == 0 and
          count(db_url, "atlas.uni_ops_governed_case_decision_events_v1") == 0,
          "This proof requires a fresh source-case and decision fixture")
    check(sql(db_url, "SELECT count(*) FROM atlas.subject_disclosure_decision_events_v1 "
              "WHERE ledger_id=" + literal(ledger) + "::uuid AND "
              "subject_domain='farm_operations' AND subject_id="
              + literal(subject) + "::uuid") == "0",
          "Fixture already has Subject information permissions")
    before_work = count(db_url, "atlas.work_items")
    api, key = c1.local_status()
    identities = base.setup_auth(db_url)
    tokens = {}
    for label, expected in identities:
        token, claims = c1.sign_in(api, key, label)
        session_checked(db_url, token, identifier(expected))
        tokens[label] = token
    check(set(tokens) == {"owner", "worker", "outsider", "no-seat"},
          "Four independent local GoTrue signer identities required")

    # Native Farm custody must be established through the EXISTING
    # genuine signed public source writer, never direct fixture SQL.
    check(sql(db_url, "SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 "
              "WHERE farm_id=" + literal(farm) + "::uuid") == "0",
          "Fictional source fixture must not pregrant Farm custody")
    custody_body = {
        "p_farm_id": farm, "p_ledger_id": ledger,
        "p_review": {"cropLedgerBoundaryReviewed": True,
                     "authorityDomain": "farm_crop_operations"}
    }
    custody_rpc = "/rest/v1/rpc/establish_farm_crop_ledger_custody_self_api_v1"
    for label in ("worker", "outsider", "no-seat"):
        code, obj = c1.request(api, key, custody_rpc,
                               custody_body, tokens[label])
        check(code in (200, 401, 403) and
              (code != 200 or not isinstance(obj, dict) or
               obj.get("ok") is not True),
              "Non-root signed person established Farm custody")
    code, custody_receipt = c1.request(
        api, key, custody_rpc, custody_body, tokens["owner"])
    check(code == 200 and isinstance(custody_receipt, dict)
          and custody_receipt.get("ok") is True
          and custody_receipt.get("created") is True,
          "Current signed native Ledger root did not establish Farm custody")
    check(sql(db_url, "SELECT count(*) FROM atlas.farm_crop_ledger_custody_v1 "
              "WHERE farm_id=" + literal(farm) + "::uuid AND ledger_id="
              + literal(ledger) + "::uuid AND custody_state='active' "
              "AND established_by_principal_id="
              "(SELECT principal_id FROM atlas.principal_ledger_authorities "
              "WHERE id=" + literal(c1.ROOT_AUTHORITY) + "::uuid)") == "1",
          "Signed native custody receipt does not match established root")

    # These methods are deliberately private and NOT an application RPC.
    # 404 means absent public transport, NOT a native actor denial.
    for label in ("owner", "worker", "outsider"):
        status, _ = c1.request(
            api, key, "/rest/v1/rpc/" + REST_FUNCS[2],
            {"p_case_id": str(uuid.uuid4())}, tokens[label]
        )
        check(status in (401, 403, 404),
              "Unexpected public Company decision writer availability")
    status, _ = c1.request(
        api, key, "/rest/v1/rpc/" + REST_FUNCS[2], {}, None
    )
    check(status in (401, 403, 404), "Anonymous private writer exposed")

    owner = tokens["owner"]
    A = [literal(attention) + "::uuid", literal(ledger) + "::uuid"]
    private_signed(db_url, owner, "admit", A, want_error="42501")
    check(count(db_url, "atlas.uni_ops_governed_source_cases_v1") == 0,
          "Source case fabricated without two Subject disclosures")
    for label in ("worker", "outsider", "no-seat"):
        args = A + [literal(owner_person) + "::uuid", literal("identity"),
                    literal("grant"), literal(str(uuid.uuid4())) + "::uuid",
                    literal("Worker cannot approve this native Subject information.")]
        private_signed(db_url, tokens[label], "disclose", args,
                       want_error="42501")
        private_signed(db_url, tokens[label], "admit", A, want_error="42501")

    def disclosure(info_class, decision_kind):
        args = A + [literal(owner_person) + "::uuid", literal(info_class),
                    literal(decision_kind), literal(str(uuid.uuid4())) + "::uuid",
                    literal("An independent governor source-information decision.")]
        receipt = private_signed(db_url, owner, "disclose", args)
        check(receipt.get("currentlyGranted") is (decision_kind == "grant"),
              "Subject disclosure currentness not independently verified")
        return receipt

    disclosure("identity", "grant")
    private_signed(db_url, owner, "admit", A, want_error="42501")
    disclosure("condition", "grant")
    admitted = private_signed(db_url, owner, "admit", A)
    case = identifier(admitted["sourceCaseId"])
    replay_admit = private_signed(db_url, owner, "admit", A)
    check(identifier(replay_admit["sourceCaseId"]) == case
          and count(db_url, "atlas.uni_ops_governed_source_cases_v1") == 1
          and count(db_url, "atlas.uni_ops_farm_company_source_links_v1") == 1,
          "First-party source admission replay created another case/link")

    # One-bounded private receipt reader: no raw source, Subject, employee,
    # task or access grant is serialized. A valid case ID is not enough for a
    # non-governing signer. No public RPC can serve this reader yet.
    receipt_arg = [literal(case) + "::uuid"]
    def bounded_receipt(token, expected_decision):
        receipt = private_signed(db_url, token, "receipt", receipt_arg)
        allowed = {
            "ok", "contractVersion", "caseId", "sourceCaseRegisteredAt",
            "sourceEvidenceRecordedAt", "domainAdapterMarkedVerified",
            "latestRegisteredAdmittedRevision", "latestGovernorDecisionId",
            "latestGovernorDecisionAt", "latestGovernorDecisionOutcome",
            "currentDomainSourceStillNeedsFreshProof",
            "realSourceSubjectDisclosureWasNotGrantedByThisReader",
            "permissionToCreateOriginalWork", "permissionToAssignWorker",
            "permissionToPlacePrincipalClockCandidate",
            "permissionToAcceptActualOrDone", "permissionToAutoCreateNextWork"
        }
        check(set(receipt) == allowed, "Receipt expanded past reviewed safe fields")
        check(identifier(receipt["caseId"]) == case
              and receipt["contractVersion"] ==
                  "uni_ops_company_governed_case_receipt_v1"
              and receipt["domainAdapterMarkedVerified"] is True
              and receipt["latestRegisteredAdmittedRevision"] is True
              and receipt["currentDomainSourceStillNeedsFreshProof"] is True
              and receipt["realSourceSubjectDisclosureWasNotGrantedByThisReader"] is True,
              "Source case receipt identity/currentness disclosure changed")
        for gate in (
            "permissionToCreateOriginalWork", "permissionToAssignWorker",
            "permissionToPlacePrincipalClockCandidate",
            "permissionToAcceptActualOrDone", "permissionToAutoCreateNextWork"
        ):
            check(receipt[gate] is False, "Receipt promoted a permission: " + gate)
        latest = receipt["latestGovernorDecisionId"]
        check((latest is None if expected_decision is None
               else identifier(latest) == identifier(expected_decision)),
              "Receipt did not preserve the exact immutable latest decision")
        return receipt

    # Even genuine signed owner/worker JWTs cannot find the PRIVATE
    # receipt through PostgREST. 404 alone is not business ACL proof.
    for label in ("owner", "worker", "outsider", "no-seat"):
        code, obj = c1.request(api, key,
                               "/rest/v1/rpc/" + REST_FUNCS[3],
                               {"p_case_id": case}, tokens[label])
        check(code in (401, 403, 404)
              and not (isinstance(obj, dict) and obj.get("ok") is True),
              "Private Company receipt unexpectedly reachable over REST")
    code, obj = c1.request(api, key, "/rest/v1/rpc/" + REST_FUNCS[3],
                           {"p_case_id": case}, None)
    check(code in (401, 403, 404), "Anonymous Company receipt RPC is exposed")

    # Positive reads use verified signed JWT/session in a PRIVILEGED
    # disposable SQL probe, not a public client transport.
    bounded_receipt(owner, None)
    for label in ("worker", "outsider", "no-seat"):
        private_signed(db_url, tokens[label], "receipt",
                       receipt_arg, want_error="42501")

    # Public wrapper is source-pinned and installed DEFAULT-CLOSED only on
    # this source-verified, loopback-only fictional PG17 database. The grant
    # below is an explicitly authorized TEMPORARY TEST GRANT, never migration
    # source or a production authorization.
    rest_path = "/rest/v1/rpc/uni_ops_company_governed_case_receipt_self_api_v1"
    rest_body = {"p_case_id": case}
    wrapper = "public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)"
    for role in ("authenticated", "anon", "service_role"):
        check(sql(db_url, "SELECT has_function_privilege("
                  + literal(role) + "," + literal(wrapper)
                  + ",'EXECUTE')") == "f",
              "Source must remain ungranted before local test")
    before_status, before_obj = c1.request(api, key, rest_path, rest_body, owner)
    check(before_status in (401, 403, 404)
          and not (isinstance(before_obj, dict) and before_obj.get("ok") is True),
          "Default-closed transport unexpectedly granted before clone-only test")

    # This is never executed outside the four-user fictional source test,
    # and the exact database URL was independently constrained to local
    # 127.0.0.1 / postgres / PG17 at the start of this probe.
    sql(db_url, """
        DO $clone_only_grant$
        BEGIN
          IF current_database()<>'postgres'
             OR current_setting('server_version_num')::integer/10000<>17
             OR (SELECT count(*) FROM auth.users WHERE id IN (
                 'e5200000-0000-4000-8000-000000000001'::uuid,
                 'e5200000-0000-4000-8000-000000000002'::uuid,
                 'e5200000-0000-4000-8000-000000000003'::uuid,
                 'e5200000-0000-4000-8000-000000000004'::uuid))<>4
             OR (SELECT count(*) FROM atlas.uni_ops_governed_source_cases_v1)<>1
             OR (SELECT count(*) FROM atlas.uni_ops_governed_case_decision_events_v1)<>0
          THEN
            RAISE EXCEPTION 'Not the exact disposable signed Company source'
              USING ERRCODE='42501';
          END IF;
        END;
        $clone_only_grant$;
        GRANT EXECUTE ON FUNCTION
          public.uni_ops_company_governed_case_receipt_self_api_v1(uuid)
          TO authenticated;
        SELECT pg_notify('pgrst','reload schema');
    """)
    check(sql(db_url,"SELECT has_function_privilege('authenticated',"
              +literal(wrapper)+",'EXECUTE')") == "t"
          and sql(db_url,"SELECT has_function_privilege('anon',"
              +literal(wrapper)+",'EXECUTE')") == "f"
          and sql(db_url,"SELECT has_function_privilege('service_role',"
              +literal(wrapper)+",'EXECUTE')") == "f",
          "Temporary clone grant widened beyond authenticated")
    def rest_receipt(token, expected_decision):
        # PostgREST may reload its schema cache asynchronously, but the
        # exact case/actor/source checks must pass after the reload.
        code, result = 0, None
        for attempt in range(12):
            code, result = c1.request(api, key, rest_path, rest_body, token)
            if code == 200:
                break
            if attempt < 11:
                time.sleep(0.45)
        check(code == 200 and isinstance(result, dict),
              "Real signed governor HTTP receipt did not succeed")
        direct = bounded_receipt(token, expected_decision)
        check(result == direct,
              "PostgREST receipt differs from proven bounded private source")
        return result
    def rest_denial(token, request_body, label):
        code, data = c1.request(api, key, rest_path, request_body, token)
        check(code in (401, 403)
              and isinstance(data, dict)
              and data.get("code") == "42501"
              and not data.get("ok"),
              "Genuine signed HTTP authorization did not deny: " + label)
    rest_receipt(owner, None)
    for label in ("worker", "outsider", "no-seat"):
        rest_denial(tokens[label], rest_body, label)
    rest_denial(owner, {"p_case_id": str(uuid.uuid4())},
                "known governor / unknown source case")
    rest_denial(owner, {"p_case_id": None}, "known governor / null case")
    code, data = c1.request(api, key, rest_path, rest_body, None)
    check(code in (401, 403, 404)
          and not (isinstance(data, dict) and data.get("ok") is True),
          "Anonymous user unexpectedly read known Company case")

    def decision(token, action, reason, expected=None, outcome="hold_for_more_source",
                 error=None):
        params = [literal(case) + "::uuid", literal(attention) + "::uuid",
                  literal(ledger) + "::uuid", literal(outcome),
                  literal(reason), literal(action) + "::uuid",
                  ("NULL::uuid" if expected is None
                   else literal(expected) + "::uuid")]
        return private_signed(db_url, token, "decide", params, want_error=error)

    for label in ("worker", "outsider", "no-seat"):
        decision(tokens[label], str(uuid.uuid4()),
                 "Unauthorized actor cannot decide this case.", error="42501")
    first_action = str(uuid.uuid4())
    reason = "The genuine source needs a governing review; no Work is admitted."
    first = decision(owner, first_action, reason)
    first_event = identifier(first["decisionEventId"])
    first_receipt = bounded_receipt(owner, first_event)
    rest_receipt(owner, first_event)
    check(first_receipt["latestGovernorDecisionOutcome"] == "hold_for_more_source",
          "Receipt mutated governor choice or disclosed another outcome")
    check(first.get("newWorkCreated") is False
          and first.get("principalClockCandidateCreated") is False,
          "Source decision fabricated Work or Principal Clock")
    replay = decision(owner, first_action, reason)
    check(replay.get("replay") is True
          and replay.get("decisionEventId") == first_event,
          "Same signed decision action was not idempotent")
    decision(owner, first_action, "Conflicting replay must fail.",
             error="23505")
    check(count(db_url, "atlas.uni_ops_governed_case_decision_events_v1") == 1,
          "Changed same action generated a second governing decision")

    # A second independent signed GoTrue session of the SAME governor races
    # one prior immutable event. Exactly one choice may append.
    owner2, claims2 = c1.sign_in(api, key, "owner")
    session_checked(db_url, owner2, c1.OWNER)
    check(claims2["session_id"] != c1.jwt_payload(owner)["session_id"],
          "Racing sessions must be independent and real")
    barrier = threading.Barrier(3)
    def race(token, action):
        barrier.wait(timeout=10)
        params = [literal(case) + "::uuid", literal(attention) + "::uuid",
                  literal(ledger) + "::uuid", literal("hold_for_more_source"),
                  literal("Concurrent decision requires current source."),
                  literal(action) + "::uuid", literal(first_event) + "::uuid"]
        try:
            res = private_signed(db_url, token, "decide", params)
            return "ok", res
        except SourceSQLDenial as denied:
            return "denied", denied.code
    with ThreadPoolExecutor(max_workers=2) as pool:
        f1 = pool.submit(race, owner, str(uuid.uuid4()))
        f2 = pool.submit(race, owner2, str(uuid.uuid4()))
        barrier.wait(timeout=10)
        results = [f1.result(timeout=45), f2.result(timeout=45)]
    check(sum(x[0] == "ok" for x in results) == 1
          and sum(x == ("denied", "23505") for x in results) == 1
          and count(db_url, "atlas.uni_ops_governed_case_decision_events_v1") == 2,
          "Concurrent governor CAS must admit one and 23505-deny one")
    race_winner_event = (results[0][1] if results[0][0] == "ok"
                         else results[1][1])["decisionEventId"]
    bounded_receipt(owner, race_winner_event)
    bounded_receipt(owner2, race_winner_event)
    rest_receipt(owner, race_winner_event)
    rest_receipt(owner2, race_winner_event)
    # Withholding one class must deny even a CURRENT governor after admission.
    disclosure("condition", "withhold")
    decision(owner, str(uuid.uuid4()),
             "Revoked Subject condition must deny further decision.",
             expected=identifier(results[0][1]["decisionEventId"])
             if results[0][0] == "ok"
             else identifier(results[1][1]["decisionEventId"]),
             error="42501")
    check(count(db_url, "atlas.uni_ops_governed_case_decision_events_v1") == 2,
          "Withheld Subject disclosure did not freeze decisions")
    # The bounded receipt is historical/safe even while source condition
    # disclosure is currently WITHHELD; it does NOT claim fresh Subject
    # visibility or right to decide a new source action.
    bounded_receipt(owner, race_winner_event)
    rest_receipt(owner, race_winner_event)
    # Re-establish the information class, then revoke the *native* root:
    # this denial must be about actual current authority, not the prior
    # independent withheld-Subject denial. Only this disposable clone changes.
    disclosure("condition", "grant")
    sql(db_url, "UPDATE atlas.principal_ledger_authorities "
        "SET status='ended',ended_at=now() WHERE id="
        + literal(c1.ROOT_AUTHORITY) + "::uuid")
    check(sql(db_url, "SELECT status FROM atlas.principal_ledger_authorities "
              "WHERE id=" + literal(c1.ROOT_AUTHORITY) + "::uuid") == "ended",
          "Native governing authority did not actually end in local clone")
    latest = (results[0][1] if results[0][0] == "ok"
              else results[1][1])["decisionEventId"]
    decision(owner, str(uuid.uuid4()),
             "Revoked governing root must not decide admitted source.",
             expected=identifier(latest), error="42501")
    check(count(db_url, "atlas.uni_ops_governed_case_decision_events_v1") == 2,
          "Revoked governing authority wrote another decision")
    private_signed(db_url, owner, "receipt",
                   receipt_arg, want_error="42501")
    private_signed(db_url, owner2, "receipt",
                   receipt_arg, want_error="42501")
    rest_denial(owner, rest_body, "revoked native root first session")
    rest_denial(owner2, rest_body, "revoked native root second session")
    check(sql(db_url,"SELECT has_function_privilege('anon',"
              +literal(wrapper)+",'EXECUTE')") == "f",
          "Temporary signed test unexpectedly widened anonymous grant")

    check(count(db_url, "atlas.work_items") == before_work,
          "Company source decision unexpectedly produced canonical Work")
    check(sql(db_url, "SELECT to_regclass("
              + literal("atlas.uni_ops_p3_owner_attention_decision_events_v1")
              + ") IS NULL") == "t",
          "Two competing Company/Farm decision histories installed")

    Path(output).parent.mkdir(parents=True, exist_ok=True)
    Path(output).write_text(
        "PASS local real GoTrue sessions + privileged private source probe; "
        "two independently signed Subject disclosures; one native Farm case; "
        "one immutable Company decision chain; bounded governor-only "
        "private case receipt before/after decision, concurrent decision, "
        "Subject withholding and native root revocation; "
        "temporary authenticated PostgREST GRANT only in disposable PG17; "
        "signed governor one-case HTTP positive/negative/unknown/revoked "
        "and precise 17-field safe source read; "
        "zero new Work; NO production grant or release approval\n",
        encoding="utf-8"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--fixture-manifest", required=True)
    parser.add_argument("--output", required=True)
    a = parser.parse_args()
    run(a.db_url, a.fixture_manifest, a.output)


if __name__ == "__main__":
    main()
