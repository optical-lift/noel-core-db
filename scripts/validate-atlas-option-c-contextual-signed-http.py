#!/usr/bin/env python3
"""Held Option C P0B signed GoTrue/PostgREST test: DISPOSABLE LOCAL CLONE ONLY.

The endpoint is an existing governor-only source reader. This test cannot
certify a worker's effective field permission or authorize any deployment.
"""
import argparse
import importlib.util
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "atlas_option_c_base",HERE/"validate-atlas-work-prerequisite-signed-http.py")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1
ORG=c1.ORG
PRIMARY=c1.LEDGER_A
OPERATING=c1.LEDGER_B
OWNER_PERSON="e5200000-0000-4000-8000-000000000101"
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"
UNKNOWN_PERSON="e5200000-0000-4000-8000-000000000104"
OWNER_SECOND_ROOT="e5200000-0000-4000-8000-000000000603"
WORKER_PRIMARY_ROOT="e5200000-0000-4000-8000-000000000604"
WORKER_OPERATING_ROOT="e5200000-0000-4000-8000-000000000602"
OWNER_OPERATING_SEAT="e5200000-0000-4000-8000-000000000505"
RPC="owner_effective_subject_disclosure_review_self_api_v1"

def check(condition,reason):
    c1.check(condition,reason)

def sql(db,stmt):
    return c1.sql(db,stmt)

def request(api,key,token,ledger,person):
    return c1.rpc(api,key,RPC,{
        "p_organization_id":ORG,
        "p_ledger_id":ledger,
        "p_target_person_id":person,
        "p_limit":10,
        "p_after_work_item_id":None
    },token)

def deny(api,key,token,ledger,person,reason):
    status,body=request(api,key,token,ledger,person)
    check(status in (401,403) and isinstance(body,dict),
          reason+": governor review was not blocked at HTTP boundary")
    if token is not None:
        check(body.get("code") in ("42501","PGRST301"),
              reason+": denial did not come from signed source")
    print("PASS",reason)

def review(api,key,token,ledger,person):
    status,body=request(api,key,token,ledger,person)
    check(status==200 and isinstance(body,dict) and body.get("ok") is True,
          "governor read failed; HTTP "+str(status)+" code "+
          (str(body.get("code")) if isinstance(body,dict) else "invalid"))
    check(body.get("governorOnly") is True
          and body.get("isSignedTargetAccessProof") is False
          and body.get("signedAlternativeReaderCoverageComplete") is False,
          "governor shell falsely certified target or alternate reader coverage")
    context=body.get("contextualAuthorityReview")
    check(isinstance(context,dict)
          and context.get("doesNotAuthorizeAnyOperation") is True
          and context.get("notAFieldDisclosure") is True
          and context.get("notASignedTargetSessionProof") is True
          and context.get("notAnEffectivePermissionCertificate") is True
          and context.get("legacyDualRootIsNotUniversalAuthorityLaw") is True,
          "contextual source facts falsely implied a granted capability")
    observations=body.get("contextualOperationObservations")
    check(isinstance(observations,list) and len(observations)==1,
          "typed operation observation must be one governor-only source packet")
    operation=observations[0]
    check(operation.get("dimension")=="governing"
          and operation.get("operation")=="company_work.manage"
          and operation.get("recordKind")=="native_ledger"
          and operation.get("selectedLedgerId")==ledger
          and operation.get("selectedLedgerRootSource")==context.get("selectedLedgerRoot")
          and operation.get("legacyCompatibilitySourceCandidate")==
              context.get("legacyCompanyWorkDualRootCandidate")
          and operation.get("grantChainCoverage")=="not_verified"
          and operation.get("effectivePermission")=="verification_incomplete"
          and operation.get("sourceWriterRecheckRequired") is True
          and operation.get("doesNotAuthorizeAnyOperation") is True,
          "typed operation packet inferred execution from source root")
    for work in body.get("canonicalWork",[]):
        for subject in work.get("linkedSubjectDisclosure",{}).get("items",[]):
            fields=subject.get("contextualFieldObservations")
            check(isinstance(fields,list) and len(fields)==2,
                  "a linked Subject must have two separate typed field observations")
            for item,field,source_field in zip(fields,("identity","condition"),
                ("identityDecisionCurrentlyGrants","conditionDecisionCurrentlyGrants")):
                check(item.get("dimension")=="knowledge"
                      and item.get("operation")=="subject.read"
                      and item.get("recordKind")=="spatial.growing_object"
                      and item.get("selectedLedgerId")==ledger
                      and item.get("fieldPath")==field
                      and item.get("currentSourceGrant") is subject.get(source_field)
                      and item.get("grantChainCoverage")=="legacy_last_decision_only"
                      and item.get("effectivePermission")=="verification_incomplete"
                      and item.get("doesNotDiscloseFieldToTarget") is True,
                      "typed field observation promoted old disclosure to broad right")
    return context

def flags(context,exact,primary,is_primary):
    check(context.get("status")=="source_root_flags_only",
          "unambiguous source relationship did not resolve")
    check(context.get("selectedLedgerRoot") is exact
          and context.get("organizationPrimaryRoot") is primary
          and context.get("selectedLedgerIsOrganizationPrimary") is is_primary
          and context.get("legacyCompanyWorkDualRootCandidate") is
              (exact and primary),
          "exact/primary/source dual-root flags contradict signed fixture")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--db-url",required=True)
    ap.add_argument("--output",required=True)
    args=ap.parse_args()
    check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
        args.db_url)),
        "Refuse nonlocal database for signed Option C test")
    check(sql(args.db_url,
          "select count(*) from atlas.principal_ledger_authorities "
          "where ledger_id='"+OPERATING+"'::uuid and "
          "authority_kind='root_governing' and status='active' "
          "and ended_at is null")=="2",
          "Fictional operating Ledger must have two independently active roots")
    check(sql(args.db_url,
          "select count(*) from atlas.principal_ledger_authorities "
          "where ledger_id='"+PRIMARY+"'::uuid and "
          "authority_kind='root_governing' and status='active' "
          "and ended_at is null")=="1",
          "Fictional primary Ledger must initially have owner root only")
    api,key=c1.local_status()
    base.setup_auth(args.db_url)
    sessions={}
    for name,expected in (("owner",c1.OWNER),("worker",c1.WORKER),
                          ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==expected and bool(claims.get("session_id")),
              "independent local GoTrue person/session mismatch")
        check(sql(args.db_url,"select count(*) from auth.sessions "
                  "where id='"+claims["session_id"]+"'::uuid and "
                  "user_id='"+expected+"'::uuid")=="1",
              "signed session not durable in local auth.sessions")
        sessions[name]=(token,claims)
    owner=sessions["owner"][0]
    worker=sessions["worker"][0]
    outsider=sessions["outsider"][0]
    no_seat=sessions["no-seat"][0]
    print("PASS four independent real local signed GoTrue sessions")

    flags(review(api,key,owner,OPERATING,WORKER_PERSON),True,False,False)
    flags(review(api,key,owner,OPERATING,OWNER_PERSON),True,True,False)
    flags(review(api,key,owner,PRIMARY,WORKER_PERSON),False,False,True)
    print("PASS two simultaneous operating roots and independent primary scope")

    # Only the governor sees these facts. Distinct known current SOURCE
    # decisions do not certify the worker can read private records.
    status,full=request(api,key,owner,OPERATING,WORKER_PERSON)
    check(status==200 and full.get("ok") is True,
          "held signed source review unavailable for typed field fixture")
    originals=full.get("canonicalWork",[])
    check(len(originals)==1 and
          originals[0].get("workItemId")=="e5200000-0000-4000-8000-000000000903",
          "fictional source Work was not observed by canonical identity")
    linked=originals[0].get("linkedSubjectDisclosure",{}).get("items",[])
    check(len(linked)==1 and
          linked[0].get("subjectId")=="e5200000-0000-4000-8000-000000000902",
          "one original linked Subject not returned")
    typed=linked[0].get("contextualFieldObservations",[])
    check(len(typed)==2 and
          typed[0].get("fieldPath")=="identity" and
          typed[0].get("currentSourceGrant") is True and
          typed[1].get("fieldPath")=="condition" and
          typed[1].get("currentSourceGrant") is False,
          "independent identity/condition source grants were collapsed")
    print("PASS one canonical Work linked Subject, distinct typed field source states")


    missing=review(api,key,owner,OPERATING,UNKNOWN_PERSON)
    check(missing.get("status")=="unresolved"
          and all(missing.get(k) is None for k in (
              "selectedLedgerRoot","organizationPrimaryRoot",
              "legacyCompanyWorkDualRootCandidate",
              "selectedLedgerIsOrganizationPrimary")),
          "target without a linked Principal was assigned imaginary authority")
    print("PASS unknown Principal returns null, not false authority certainty")

    deny(api,key,worker,OPERATING,OWNER_PERSON,
         "exact operating root does not bypass current legacy primary-root guard")
    deny(api,key,outsider,OPERATING,OWNER_PERSON,
         "unrelated actor cannot preview governor source facts")
    deny(api,key,no_seat,OPERATING,OWNER_PERSON,
         "no-root participant cannot preview governor source facts")
    deny(api,key,None,OPERATING,OWNER_PERSON,
         "anonymous actor cannot preview governor source facts")
    # C1's outsider has an active seat on B (the operating Ledger), but
    # no seat on A (the primary Ledger). Test the real no-seat case.
    deny(api,key,owner,PRIMARY,"e5200000-0000-4000-8000-000000000103",
         "governor cannot enumerate Person with no selected-Ledger Seat")

    # Only local disposable root decisions; no production Person/grants.
    sql(args.db_url,
        "INSERT INTO atlas.principal_ledger_authorities("
        "id,principal_id,ledger_id,authority_kind,status,basis) VALUES("
        "'"+WORKER_PRIMARY_ROOT+"'::uuid,"
        "'e5200000-0000-4000-8000-000000000112'::uuid,"
        "'"+PRIMARY+"'::uuid,'root_governing','active',"
        "'option_c_disposable_cross_ledger_positive')")
    flags(review(api,key,owner,OPERATING,WORKER_PERSON),True,True,False)
    flags(review(api,key,worker,OPERATING,OWNER_PERSON),True,True,False)
    print("PASS newly lawful second governor independently signed")

    sql(args.db_url,
        "UPDATE atlas.principal_ledger_authorities SET "
        "status='ended',ended_at=now() WHERE id='"+WORKER_PRIMARY_ROOT+"'::uuid")
    flags(review(api,key,owner,OPERATING,WORKER_PERSON),True,False,False)
    deny(api,key,worker,OPERATING,OWNER_PERSON,
         "worker primary-root withdrawal invalidates existing signed access")
    sql(args.db_url,
        "UPDATE atlas.principal_ledger_authorities SET "
        "status='ended',ended_at=now() WHERE id='"+WORKER_OPERATING_ROOT+"'::uuid")
    flags(review(api,key,owner,OPERATING,WORKER_PERSON),False,False,False)
    print("PASS independent authority-chain withdrawal reflected immediately")

    sql(args.db_url,
        "UPDATE ledger.seats SET seat_state='ended',ended_at=now() "
        "WHERE id='"+OWNER_OPERATING_SEAT+"'::uuid")
    deny(api,key,owner,OPERATING,WORKER_PERSON,
         "ended current governor operating Seat invalidates signed access")
    sql(args.db_url,
        "UPDATE ledger.seats SET seat_state='active',ended_at=NULL "
        "WHERE id='"+OWNER_OPERATING_SEAT+"'::uuid")
    flags(review(api,key,owner,OPERATING,WORKER_PERSON),False,False,False)
    sql(args.db_url,
        "UPDATE atlas.principal_ledger_authorities SET "
        "status='ended',ended_at=now() "
        "WHERE id='"+OWNER_SECOND_ROOT+"'::uuid")
    deny(api,key,owner,OPERATING,WORKER_PERSON,
         "ending one co-root blocks its signed operating authority")
    flags(review(api,key,owner,PRIMARY,WORKER_PERSON),False,False,True)
    print("PASS one governing root's withdrawal leaves independent primary root")

    sql(args.db_url,
        "DELETE FROM auth.sessions WHERE id='"+
        sessions["owner"][1]["session_id"]+"'::uuid")
    deny(api,key,owner,PRIMARY,WORKER_PERSON,
         "revoked GoTrue session denies otherwise still-valid primary governor")

    Path(args.output).parent.mkdir(parents=True,exist_ok=True)
    Path(args.output).write_text(
        "PASS Option C exact versus primary, concurrent governors, source "
        "ambiguity, signed negative access, independent chains, ended Seat, "
        "withdrawn authority and revoked GoTrue session; DISPOSABLE LOCAL ONLY.\n",
        encoding="utf-8")
    print("PASS all held Option C real signed local tests")

if __name__=="__main__":
    main()
