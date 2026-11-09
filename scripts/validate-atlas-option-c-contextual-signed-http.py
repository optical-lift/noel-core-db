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

def governed_action(api,key,token,name,args):
    status,body=c1.rpc(api,key,name,args,token)
    valid=(status==200 and isinstance(body,dict)
           and body.get("code") not in ("not_found","review_required")
           and body.get("ok",True) is True)
    if not valid and name=="respond_connected_person_company_work_self_api_v1":
        # No protected payload, SQL, Person, token or free-form source text
        # can escape the local signed test; classify only audited conditions.
        msg=str(body.get("message","")) if isinstance(body,dict) else ""
        code=str(body.get("code","")) if isinstance(body,dict) else ""
        recognized=(
          ("Pending Person-native offer required","pending_offer"),
          ("Work or exact Ledger connection changed before uptake","stale_work"),
          ("Another Person already owns this Work","active_responsibility"),
          ("Offered Work source no longer matches native Ledger","work_relevance"),
          ("Ordinary Company Work result policy unavailable","result_policy"),
          ("Person-native responsibility must trace to the exact accepted offer",
           "allocation_offer_provenance"),
          ("Active Work allocation cannot name an inactive assigning membership",
           "assigner_membership"),
          ("Exact Person-native receiver uptake provenance required","recipient_basis"),
        )
        reason=next((tag for phrase,tag in recognized if phrase in msg),
                    {"42501":"source_denied","23514":"other_source_guard",
                     "23505":"uniqueness","22023":"invalid_input",
                     "PGRST301":"signed_session"}.get(code,"other_failure"))
        print("OPTION_C_P1B_ACCEPTANCE_CLASS="+reason)
    check(valid,
          "Signed canonical source command failed: "+name+" HTTP "+str(status))
    return body

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
    # The protected clone restores schema/roles only, not production reference
    # rows. The *released source* requires this exact ordinary Work result
    # contract when recipient uptake binds a legacy-task original. Seed that
    # contract only on loopback, never in the shared fixture or live source.
    sql(args.db_url, """
      INSERT INTO atlas.work_result_contract_policies(
        contract_key,source_domain,acceptance_mode,active,description,metadata
      ) VALUES (
        'ordinary_company_work_worker_attestation_v1',
        'organization','worker_attestation',true,
        'Disposable source-compatible ordinary Work result contract',
        '{"cloneFixture":true}'::jsonb
      ) ON CONFLICT (contract_key) DO NOTHING
    """)
    check(sql(args.db_url, """
      SELECT count(*) FROM atlas.work_result_contract_policies
      WHERE contract_key='ordinary_company_work_worker_attestation_v1'
        AND source_domain='organization'
        AND acceptance_mode='worker_attestation' AND active
    """)=="1",
      "Required source-native result policy is not uniquely active in local clone")
    # Fictional spatial sources are established on the loopback disposable
    # Postgres only. Do not add this DML to the shared guarded source fixture.
    sql(args.db_url, """
      INSERT INTO atlas.farms(id,stable_key,name,organization_id,organization_unit_id)
      VALUES (
        'e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-farm','Option C Fictional Farm',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000802'
      )
    """)
    sql(args.db_url, """
      INSERT INTO atlas.zones(id,farm_id,stable_key,label)
      VALUES (
        'e5200000-0000-4000-8000-000000000911',
        'e5200000-0000-4000-8000-000000000901',
        'option-c-fictional-zone','Fictional source Zone'
      )
    """)
    sql(args.db_url, """
      INSERT INTO atlas.organization_memberships(
        id,organization_id,user_id,person_id,role,active
      ) VALUES (
        'e5200000-0000-4000-8000-000000000913',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000001',
        'e5200000-0000-4000-8000-000000000101',
        'owner',true
      ),(
        'e5200000-0000-4000-8000-000000000914',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000002',
        'e5200000-0000-4000-8000-000000000102',
        'member',true
      )
    """)
    sql(args.db_url, """
      INSERT INTO atlas.growing_objects(id,farm_id,zone_id,stable_key,label,object_type)
      VALUES (
        'e5200000-0000-4000-8000-000000000902',
        'e5200000-0000-4000-8000-000000000901',
        'e5200000-0000-4000-8000-000000000911',
        'option-c-fictional-bed','Fictional Bed for source review','bed'
      ),(
        'e5200000-0000-4000-8000-000000000918',
        'e5200000-0000-4000-8000-000000000901',
        'e5200000-0000-4000-8000-000000000911',
        'option-c-private-bed','Fictional withheld Bed','bed'
      )
    """)
    check(sql(args.db_url,
          "select count(*) from atlas.growing_objects where id="
          "'e5200000-0000-4000-8000-000000000902'::uuid")=="1",
          "Fictional local-only subject was not established")

    # The global DML fixture scanner intentionally prohibits the word GRANT
    # even as a data literal. Only this disposable/local psql test setup
    # establishes fictional field events; it does not test a live writer.
    sql(args.db_url, """
      INSERT INTO atlas.subject_disclosure_decision_events_v1(
        id,organization_id,ledger_id,target_person_id,
        subject_domain,subject_kind,subject_id,disclosure_class,
        decision_kind,source_action_id,reason,decided_by_person_id
      ) VALUES (
        'e5200000-0000-4000-8000-000000000907',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000402',
        'e5200000-0000-4000-8000-000000000102',
        'spatial','growing_object','e5200000-0000-4000-8000-000000000902',
        'identity','grant','e5200000-0000-4000-8000-000000000909',
        'Fictional governor grants only this Subject identity source.',
        'e5200000-0000-4000-8000-000000000101'
      ),(
        'e5200000-0000-4000-8000-000000000908',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000402',
        'e5200000-0000-4000-8000-000000000102',
        'spatial','growing_object','e5200000-0000-4000-8000-000000000902',
        'condition','withhold','e5200000-0000-4000-8000-000000000910',
        'Fictional governor withholds independent Subject condition.',
        'e5200000-0000-4000-8000-000000000101'
      )
    """)
    check(sql(args.db_url, "select count(*) from atlas.subject_disclosure_decision_events_v1 "
              "where organization_id='"+ORG+"'::uuid and "
              "subject_id='e5200000-0000-4000-8000-000000000902'::uuid")=="2",
          "Fictional field source decisions were not established")
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

    # Actual canonical source chain, not a fabricated original Work row:
    # physical Zone -> legacy Task -> existing canonical Work adoption trigger.
    # The first temporary legacy allocation is released by that same task
    # adapter, preserving the ONE original Work for a real signed Person offer.
    sql(args.db_url, """
      INSERT INTO atlas.tasks(
        id,organization_id,farm_id,zone_id,title,task_type,status,
        visibility_scope,assigned_user_id,created_by_user_id,note,metadata
      ) VALUES (
        'e5200000-0000-4000-8000-000000000912',
        'e5200000-0000-4000-8000-000000000801',
        'e5200000-0000-4000-8000-000000000901',
        'e5200000-0000-4000-8000-000000000911',
        'Prepare fictional growing Bed','general','open',
        'assigned_worker','e5200000-0000-4000-8000-000000000002',
        'e5200000-0000-4000-8000-000000000001',
        'Inspect and prepare only the named Bed in the synthetic Zone.',
        '{"execution_do":"Prepare the named growing bed",'
        '"execution_done_when":"Bed preparation is complete",'
        '"display_action":"Prepare","display_subject":"Fictional growing bed"}'::jsonb
      )
    """)
    work=sql(args.db_url,
       "SELECT w.id::text FROM atlas.work_items w "
       "WHERE w.source_object_type='legacy_task' AND "
       "w.source_object_id='e5200000-0000-4000-8000-000000000912'::uuid "
       "AND w.organization_id='"+ORG+"'::uuid AND w.work_state='open'")
    check(bool(re.fullmatch(r"[0-9a-f-]{36}",work)),
          "Canonical task adapter failed to create exactly one original Work")
    check(sql(args.db_url,
       "SELECT count(*) FROM atlas.work_allocations a "
       "WHERE a.work_item_id='"+work+"'::uuid "
       "AND a.allocation_role='responsible' AND a.state='active'")=="1",
       "Original legacy source did not establish responsible Work")

    # Removing its old execution-carrier assignment must preserve Work,
    # and remove only that transitional allocation. The recipient will
    # accept the SAME canonical Work via governed Person-native offer.
    sql(args.db_url, """
      UPDATE atlas.tasks
      SET assigned_user_id=NULL,visibility_scope='farm_shared'
      WHERE id='e5200000-0000-4000-8000-000000000912'
    """)
    check(sql(args.db_url,
       "SELECT count(*) FROM atlas.work_allocations a "
       "WHERE a.work_item_id='"+work+"'::uuid "
       "AND a.allocation_role='responsible' AND a.state='active'")=="0"
       and sql(args.db_url,"SELECT count(*) FROM atlas.work_items "
           "WHERE id='"+work+"'::uuid AND work_state='open'")=="1",
       "Legacy adapter must release the temporary allocation and preserve original Work")
    print("PASS original source-backed Task adoption and preserved Work identity")

    flags(review(api,key,owner,OPERATING,WORKER_PERSON),True,False,False)
    flags(review(api,key,owner,OPERATING,OWNER_PERSON),True,True,False)
    flags(review(api,key,owner,PRIMARY,WORKER_PERSON),False,False,True)
    print("PASS two simultaneous operating roots and independent primary scope")

    # Exact native Farm crop custody must be established by the genuine
    # current governor using the existing public source-owned API.
    custody=governed_action(api,key,owner,
      "establish_farm_crop_ledger_custody_self_api_v1",{
        "p_farm_id":"e5200000-0000-4000-8000-000000000901",
        "p_ledger_id":OPERATING,
        "p_review":{"cropLedgerBoundaryReviewed":True,
                    "authorityDomain":"farm_crop_operations"}})
    check(bool(custody.get("custodyId"))
          and custody.get("confersPersonAccess") is False,
          "Signed Farm/Ledger custody must not imply Person disclosure")
    relevance=governed_action(api,key,owner,
      "establish_company_work_native_ledger_relevance_self_api_v1",{
        "p_work_item_id":work,"p_ledger_id":OPERATING,
        "p_evidence_basis":{
          "evidenceClass":"owner_attestation",
          "sourceRef":"atlas.tasks:e5200000-0000-4000-8000-000000000912",
          "reason":"Fictional Bed preparation Task serves this exact governed operating Ledger."}})
    check(relevance.get("workItemId")==work
          and relevance.get("ledgerId")==OPERATING
          and relevance.get("evidenceKind")=="owner_attested"
          and relevance.get("isSourceVerified") is False,
          "Signed Work relevance must preserve honest owner-attested evidence")

    # Same original Work: governor offers -> actual recipient accepts.
    offered=governed_action(api,key,owner,
      "offer_connected_person_company_work_owner_self_api_v1",{
        "p_organization_id":ORG,"p_ledger_id":OPERATING,
        "p_work_item_id":work,
        "p_target_canonical_person_id":WORKER_PERSON,
        "p_reason":"Offer the single original fictional Bed task to the connected worker."})
    check(offered.get("state")=="offered"
          and offered.get("responsibilityChanged") is False
          and bool(offered.get("offerId")),
          "Source offer must not preassign or infer recipient consent")
    accepted=governed_action(api,key,worker,
      "respond_connected_person_company_work_self_api_v1",{
        "p_offer_id":offered["offerId"],"p_decision":"accepted"})
    check(accepted.get("state")=="accepted",
          "Worker acceptance must be independently authenticated")
    check(sql(args.db_url,
       "SELECT count(*) FROM atlas.work_allocations "
       "WHERE work_item_id='"+work+"'::uuid "
       "AND assignee_canonical_person_id='"+WORKER_PERSON+"'::uuid "
       "AND allocation_role='responsible' AND state='active'")=="1",
       "Accepted source must hold ONE canonical Person Work allocation")
    check(sql(args.db_url,
       "SELECT count(*) FROM atlas.work_items WHERE id='"+work+
       "'::uuid AND source_object_id="
       "'e5200000-0000-4000-8000-000000000912'::uuid")=="1",
       "Original Work identity changed during recipient acceptance")
    print("PASS signed governor original-Work offer and independent recipient acceptance")

    physical=governed_action(api,key,owner,
      "work_growing_object_context_review_self_api_v1",{
        "p_ledger_id":OPERATING,"p_work_item_id":work})
    candidate_ids={x.get("objectId") for x in physical.get("candidates",[])}
    check(physical.get("ok") is True and
          candidate_ids=={
            "e5200000-0000-4000-8000-000000000902",
            "e5200000-0000-4000-8000-000000000918"},
          "Physical review did not establish exact Task/Farm/Zone Bed candidates")
    for obj,stable in (
        ("e5200000-0000-4000-8000-000000000902",
         "option-c-fictional-bed"),
        ("e5200000-0000-4000-8000-000000000918",
         "option-c-private-bed")):
        context=governed_action(api,key,owner,
          "establish_work_growing_object_context_self_api_v1",{
             "p_ledger_id":OPERATING,"p_work_item_id":work,
             "p_object_id":obj,
             "p_review":{"humanConfirmed":True,
                 "reviewedWorkStableKey":physical["workStableKey"],
                 "reviewedObjectKey":stable}})
        check(context.get("ok") is True
              and context.get("workItemId")==work
              and context.get("confersAccess") is False,
              "Physical context link cannot create Work or disclose private fields")
    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_item_context_links "
       "WHERE work_item_id='"+work+"'::uuid "
       "AND subject_domain='spatial' AND subject_kind='growing_object'")=="2",
       "Signed physical source did not establish exactly two guarded context links")
    print("PASS governor-attested physical Work/Bed source links, no disclosure power")

    # The underlying source has field-specific decisions, but the shared
    # source-custody guard forbids inventing an original Work/Bed link.
    # These two SELECTs validate only the current last-decision helper.
    # The field packet's signed Work-linked projection remains an OPEN gate.
    identity=sql(args.db_url,
        "SELECT atlas.has_current_subject_disclosure_v1('"+OPERATING+"'::uuid,"
        "'"+WORKER_PERSON+"'::uuid,'spatial','growing_object',"
        "'e5200000-0000-4000-8000-000000000902'::uuid,'identity')")
    condition=sql(args.db_url,
        "SELECT atlas.has_current_subject_disclosure_v1('"+OPERATING+"'::uuid,"
        "'"+WORKER_PERSON+"'::uuid,'spatial','growing_object',"
        "'e5200000-0000-4000-8000-000000000902'::uuid,'condition')")
    check(identity=="t" and condition=="f",
          "separate fictional Bed identity/condition current source decisions disagree")
    print("PASS distinct subject field source truth (not signed target disclosure)")

    # This is the non-vacuous P1B proof: one existing Work, two original
    # physically-linked Beds, two separately typed field responses per Bed.
    status,governor_rows=request(api,key,owner,OPERATING,WORKER_PERSON)
    check(status==200 and isinstance(governor_rows,dict)
          and governor_rows.get("ok") is True,
          "Signed governor response unavailable for linked field proof")
    originals=governor_rows.get("canonicalWork",[])
    check(len(originals)==1 and originals[0].get("workItemId")==work
          and originals[0].get("allocationId"),
          "Work-linked review must name the same original accepted Work exactly")
    packet=originals[0].get("linkedSubjectDisclosure",{})
    subjects=packet.get("items",[])
    check(len(subjects)==2 and packet.get("hasMore") is False,
          "Signed governor response must return both physical Work-linked Beds")
    subject_by_id={item.get("subjectId"):item for item in subjects}
    check(set(subject_by_id)=={
          "e5200000-0000-4000-8000-000000000902",
          "e5200000-0000-4000-8000-000000000918"},
          "Signed governor Work-linked subject IDs differ from source")
    for sub_id,expected in (
         ("e5200000-0000-4000-8000-000000000902",(True,False)),
         ("e5200000-0000-4000-8000-000000000918",(False,False))):
        fields=subject_by_id[sub_id].get("contextualFieldObservations")
        check(isinstance(fields,list) and len(fields)==2,
              "Each real Work-linked Subject must carry exactly two typed fields")
        for index,(field,source_grant) in enumerate(zip(
                ("identity","condition"),expected)):
            item=fields[index]
            check(item.get("fieldPath")==field
                  and item.get("operation")=="subject.read"
                  and item.get("recordKind")=="spatial.growing_object"
                  and item.get("selectedLedgerId")==OPERATING
                  and item.get("currentSourceGrant") is source_grant
                  and item.get("grantChainCoverage")=="legacy_last_decision_only"
                  and item.get("effectivePermission")=="verification_incomplete"
                  and item.get("doesNotDiscloseFieldToTarget") is True,
                  "Separate actual Work-linked field observation is not source true")
    print("PASS signed governor two Work-linked Bed packets with distinct field states")

    # A real accepted Work allocation NEVER grants the attached Bed's
    # private identity/condition by itself. The target's own source-read
    # routes must omit withheld Bed B and withhold Bed A condition.
    status,visible=c1.rpc(api,key,
        "connected_person_work_subject_links_self_api_v1",{
           "p_organization_id":ORG,"p_ledger_id":OPERATING,
           "p_work_item_id":work,"p_limit":30,
           "p_after_subject_id":None},worker)
    check(status==200 and isinstance(visible,dict) and
          visible.get("ok") is True and
          visible.get("undisclosedSubjectsOmitted") is True and
          visible.get("items") is not None and
          len(visible["items"])==1 and
          visible["items"][0].get("subjectId")==
            "e5200000-0000-4000-8000-000000000902" and
          visible.get("hasMore") is False and
          "e5200000-0000-4000-8000-000000000918" not in str(visible) and
          "Fictional withheld Bed" not in str(visible),
          "Worker listed Bed without a valid separate identity disclosure")
    detail_args={
        "p_organization_id":ORG,"p_ledger_id":OPERATING,
        "p_work_item_id":work,"p_subject_domain":"spatial",
        "p_subject_kind":"growing_object",
        "p_subject_id":"e5200000-0000-4000-8000-000000000902"}
    status,detail=c1.rpc(api,key,
      "connected_person_original_work_subject_self_api_v1",detail_args,worker)
    check(status==200 and isinstance(detail,dict)
          and detail.get("subjectId")==detail_args["p_subject_id"]
          and detail.get("conditionDisclosed") is False
          and detail.get("condition") is None
          and detail.get("cropPlacementDetailsDisclosed") is False
          and detail.get("notesAndMetadataDisclosed") is False
          and detail.get("fullFarmReaderAccessGranted") is False,
          "Worker's allowed Bed identity improperly exposed condition/private fields")
    hidden=dict(detail_args,
      p_subject_id="e5200000-0000-4000-8000-000000000918")
    status,denied=c1.rpc(api,key,
      "connected_person_original_work_subject_self_api_v1",hidden,worker)
    check(status==403 and isinstance(denied,dict)
          and denied.get("code")=="42501",
          "Direct read disclosed the completely withheld Bed")
    status,outsider=c1.rpc(api,key,
      "connected_person_work_subject_links_self_api_v1",{
        "p_organization_id":ORG,"p_ledger_id":OPERATING,
        "p_work_item_id":work,"p_limit":30,
        "p_after_subject_id":None},outsider)
    check(status==403 and isinstance(outsider,dict)
          and outsider.get("code")=="42501",
          "Unassigned Person obtained the same Work's private Subject list")
    print("PASS signed worker sees only authorized Bed identity; condition and other Bed withheld")


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
        "ambiguity, lawful one-original Work source/accepted receiver/Bed links, "
        "typed identity-vs-condition source projection, signed worker nondiscovery, "
        "withdrawn authority and revoked GoTrue session; DISPOSABLE LOCAL ONLY.\n",
        encoding="utf-8")
    print("PASS all held Option C real signed local tests")

if __name__=="__main__":
    main()
