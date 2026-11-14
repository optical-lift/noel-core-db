#!/usr/bin/env python3
"""Genuine distinct local GoTrue + PostgREST W07 comment proof.

DISPOSABLE production-schema clone ONLY. Requires the existing synthetic C1
fixture, synthetic native-Work allocation fixture, and held W07 candidate SQL.
No production URL, real Person, email, notification, or actual Work creation.
A missing RPC (404/PGRST202) is a FAILURE, not permission denial.
"""
import argparse
import importlib.util
import json
import re
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location(
    "w07_existing_signed_helper",
    HERE / "validate-atlas-work-prerequisite-signed-http.py",
)
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1 = base.c1
ORG = c1.ORG
LEDGER = c1.LEDGER_A
OTHER_LEDGER = c1.LEDGER_B
WORK = "e5200000-0000-4000-8000-000000000902"
OFFER = "e5200000-0000-4000-8000-000000000982"
OWNER_PERSON = "e5200000-0000-4000-8000-000000000101"
WORKER_PERSON = "e5200000-0000-4000-8000-000000000102"
WRONG_WORK = "e5200000-0000-4000-8000-000000000901"
WORK_PARTICIPATION = "e5200000-0000-4000-8000-000000000903"
PARTICIPANT_PERSON = "e5200000-0000-4000-8000-000000000103"
OWNER_MEMBERSHIP = "e5200000-0000-4000-8000-000000000971"
PARTICIPANT_MEMBERSHIP = "e5200000-0000-4000-8000-000000000973"
OWNER_ALLOCATION = "e5200000-0000-4000-8000-000000000984"
PARTICIPATION_OFFER = "e5200000-0000-4000-8000-000000000985"
PARTICIPANT_ALLOCATION = "e5200000-0000-4000-8000-000000000986"
PARTICIPANT_SEAT = "e5200000-0000-4000-8000-000000000573"
ALLOC = "e5200000-0000-4000-8000-000000000983"
ACTION_OWNER = "e5200000-0000-4000-8000-000000000d01"
ACTION_WORKER = "e5200000-0000-4000-8000-000000000d02"
ACTION_THIRD = "e5200000-0000-4000-8000-000000000d03"
ACTION_RACE_DIFFERENT = "e5200000-0000-4000-8000-000000000d04"
ACTION_RACE_IDENTICAL = "e5200000-0000-4000-8000-000000000d05"
ACTION_PARTICIPATION_OWNER = "e5200000-0000-4000-8000-000000000d06"
ACTION_PARTICIPATION_OTHER = "e5200000-0000-4000-8000-000000000d07"
ACTION_OCCURRENCE_COMMENT = "e5200000-0000-4000-8000-000000000d08"
ACTION_COMPLETED_SOURCE = "e5200000-0000-4000-8000-000000000d09"
ACTION_COMPLETED_NEW = "e5200000-0000-4000-8000-000000000d0a"
ACTION_PHYSICAL_COMMENT = "e5200000-0000-4000-8000-000000000d0b"
PHYSICAL_FARM = "e5200000-0000-4000-8000-000000000b31"
PHYSICAL_ZONE = "e5200000-0000-4000-8000-000000000b32"
PHYSICAL_BED = "e5200000-0000-4000-8000-000000000b33"
PHYSICAL_TASK = "e5200000-0000-4000-8000-000000000b34"
PHYSICAL_WORK_KEY = "w07-original-work-903-physical"
PHYSICAL_BED_KEY = "w07-synthetic-physical-bed"
PHYSICAL_ID_GRANT = "e5200000-0000-4000-8000-000000000b35"
PHYSICAL_CONDITION_GRANT = "e5200000-0000-4000-8000-000000000b36"
PHYSICAL_CONDITION_WITHHOLD = "e5200000-0000-4000-8000-000000000b37"
PHYSICAL_CONDITION_REGRANT = "e5200000-0000-4000-8000-000000000b38"
OCCURRENCE_SUBJECT = "e5200000-0000-4000-8000-000000000a11"
OCCURRENCE_LINK = "e5200000-0000-4000-8000-000000000a12"
DISCLOSURE_GRANT_1 = "e5200000-0000-4000-8000-000000000a13"
DISCLOSURE_WITHHOLD = "e5200000-0000-4000-8000-000000000a14"
DISCLOSURE_GRANT_2 = "e5200000-0000-4000-8000-000000000a15"
BODY_OWNER = "SYNTH_W07_OWNER_COMMENT_LOCAL_ONLY"
BODY_WORKER = "SYNTH_W07_WORKER_COMMENT_LOCAL_ONLY"
BODY_THIRD = "SYNTH_W07_OWNER_SECOND_LOCAL_ONLY"
READ = "read_native_original_work_comments_self_api_v1"
WRITE = "append_native_original_work_comment_self_api_v1"

# Only constant, secret-free test stage labels are written on failure.
# Underlying local DB/JWT/HTTP diagnostics remain in protected runner scratch.
W07_STAGE = "setup"

def mark_stage(label):
    global W07_STAGE
    W07_STAGE = label


def check(value, message):
    base.check(value, message)


def sql(db_url, statement):
    return base.sql(db_url, statement)


def rpc(api, key, token, name, args):
    return base.rpc(api, key, token, name, args)


def permitted(api, key, token, name, args):
    code, packet = rpc(api, key, token, name, args)
    check(code == 200 and isinstance(packet, dict) and packet.get("ok") is True,
          "%s: missing signed source success; HTTP %s (%s)" %
          (name, code, str(packet)[:180]))
    return packet


def forbidden(api, key, token, name, args, description):
    code, packet = rpc(api, key, token, name, args)
    check(code in (401, 403) and isinstance(packet, dict)
          and packet.get("code") == "42501",
          "%s: expected real 42501, NEVER 404/unavailable; got %s, %s" %
          (description, code, str(packet)[:160]))
    check(BODY_OWNER not in json.dumps(packet)
          and BODY_WORKER not in json.dumps(packet),
          description + ": denial leaked a comment")
    print("PASS", description)


def scope(work=WORK, ledger=LEDGER):
    return {"p_organization_id": ORG,
            "p_ledger_id": ledger,
            "p_work_item_id": work}


def write_args(action, body, work=WORK, ledger=LEDGER):
    return {**scope(work, ledger),
            "p_source_action_id": action,
            "p_body": body}


def read_args(work=WORK, ledger=LEDGER, limit=40, after=None):
    return {**scope(work, ledger),
            "p_limit": limit,
            "p_after_recorded_at": after[0] if after else None,
            "p_after_comment_id": after[1] if after else None}


def simultaneous_writes(api, key, token, action, bodies):
    """Exactly two independent simultaneous localhost HTTP requests.

    This exercises database locking and the unique action receipt. It cannot
    be used against a remote API because main() validates the local endpoint.
    Each thread creates its own PostgREST connection; no shared SQL session.
    """
    check(len(bodies) == 2, "W07 race must use precisely two writers")
    gate = Barrier(2, timeout=10)

    def send(body):
        gate.wait()
        return rpc(api, key, token, WRITE, write_args(action, body))

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(send, body) for body in bodies]
        return [future.result(timeout=30) for future in futures]


def independently_accepted_participant_trial(db_url, api, key, owner, other, no_seat):
    """Only a fictional, separately accepted membership participant on Work 903.

    Preserve the preexisting C1 Work 902 Person-native responsibility unchanged.
    The signed third actor is originally denied and must remain denied after
    receiving a membership and native Ledger seat but BEFORE receiver acceptance.
    Work participation uses the existing guarded offer/acceptance source.
    """
    w = WORK_PARTICIPATION
    forbidden(api, key, other, READ, read_args(work=w),
              "third Person without accepted participation denied")

    # The recipient has both an exact native Ledger connection AND an active
    # institutional compatibility carrier; neither alone discloses Work.
    sql(db_url, """
      INSERT INTO atlas.organization_memberships
        (id,organization_id,user_id,person_id,role,active)
      VALUES
        ('%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,'owner',true),
        ('%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,'member',true)
    """ % (OWNER_MEMBERSHIP,ORG,c1.OWNER,OWNER_PERSON,
           PARTICIPANT_MEMBERSHIP,ORG,c1.OUTSIDER,PARTICIPANT_PERSON))
    sql(db_url, """
      INSERT INTO ledger.seats
        (id,ledger_id,person_entity_id,seat_state,seat_basis)
      VALUES ('%s'::uuid,'%s'::uuid,'%s'::uuid,'active',
              '{"cloneFixture":true}'::jsonb)
    """ % (PARTICIPANT_SEAT,LEDGER,PARTICIPANT_PERSON))
    forbidden(api,key,other,READ,read_args(work=w),
              "native Ledger seat and membership do not admit third Person")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_PARTICIPATION_OTHER,"not accepted",work=w),
              "native Ledger seat without accepted allocation cannot append")

    # Responsibility is separately attached to an existing original Work via
    # the governed membership self-adoption provenance of this fictional C1 Work.
    sql(db_url, """
      INSERT INTO atlas.work_allocations(
        id,organization_id,work_item_id,assignee_membership_id,
        assigned_by_membership_id,allocation_role,state,
        establishment_basis_kind,establishment_basis,metadata
      ) VALUES (
        '%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,
        '%s'::uuid,'responsible','active',
        'self_adoption',
        jsonb_build_object(
          'contractVersion','exact_work_responsibility_establishment_v2',
          'basisKind','self_adoption',
          'organizationId','%s','workItemId','%s',
          'assigneeMembershipId','%s','actorMembershipId','%s',
          'sourceKind','synthetic_original_work','sourceId','%s'
        ),
        '{"cloneFixture":"w07_member_source"}'::jsonb
      )
    """ % (OWNER_ALLOCATION,ORG,w,OWNER_MEMBERSHIP,
           OWNER_MEMBERSHIP,ORG,w,OWNER_MEMBERSHIP,OWNER_MEMBERSHIP,w))

    sql(db_url, """
      INSERT INTO atlas.company_work_participation_offers (
        id,organization_id,work_item_id,
        offered_from_responsibility_allocation_id,
        offered_by_person_entity_id,offered_by_membership_id_compatibility,
        target_person_entity_id,target_membership_id_compatibility,
        allocation_role,offer_state,reason
      ) VALUES (
        '%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,
        '%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,
        'participant','offered','Synthetic third Person participation case'
      )
    """ % (PARTICIPATION_OFFER,ORG,w,OWNER_ALLOCATION,
           OWNER_PERSON,OWNER_MEMBERSHIP,
           PARTICIPANT_PERSON,PARTICIPANT_MEMBERSHIP))
    forbidden(api,key,other,READ,read_args(work=w),
              "offered but unaccepted third Person cannot read Work")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_PARTICIPATION_OTHER,"offer only",work=w),
              "unaccepted offer cannot grant comment writing")

    sql(db_url, """
      INSERT INTO atlas.work_allocations(
        id,organization_id,work_item_id,assignee_membership_id,
        assigned_by_membership_id,allocation_role,state,
        establishment_basis_kind,establishment_basis,metadata
      ) VALUES (
        '%s'::uuid,'%s'::uuid,'%s'::uuid,'%s'::uuid,
        '%s'::uuid,'participant','active',
        'receiver_acceptance',
        jsonb_build_object(
          'contractVersion','company_work_participation_establishment_v1',
          'basisKind','receiver_acceptance',
          'organizationId','%s','workItemId','%s',
          'assigneeMembershipId','%s','actorMembershipId','%s',
          'allocationRole','participant',
          'sourceKind','company_work_participation_offer',
          'sourceId','%s'
        ),
        '{"cloneFixture":"w07_accepted_participant"}'::jsonb
      )
    """ % (PARTICIPANT_ALLOCATION,ORG,w,PARTICIPANT_MEMBERSHIP,
           PARTICIPANT_MEMBERSHIP,ORG,w,
           PARTICIPANT_MEMBERSHIP,PARTICIPANT_MEMBERSHIP,PARTICIPATION_OFFER))
    sql(db_url, """
      UPDATE atlas.company_work_participation_offers SET
        offer_state='accepted',resolved_at=now(),
        resolved_by_person_entity_id='%s'::uuid,
        resolved_by_membership_id_compatibility='%s'::uuid,
        accepted_allocation_id='%s'::uuid
      WHERE id='%s'::uuid
    """ % (PARTICIPANT_PERSON,PARTICIPANT_MEMBERSHIP,
           PARTICIPANT_ALLOCATION,PARTICIPATION_OFFER))
    check(sql(db_url, """
      SELECT count(*) FROM atlas.company_work_participation_offers o
      JOIN atlas.work_allocations a ON a.id=o.accepted_allocation_id
      WHERE o.id='%s'::uuid AND o.offer_state='accepted'
        AND o.resolved_by_person_entity_id='%s'::uuid
        AND a.assignee_membership_id='%s'::uuid
        AND a.establishment_basis->>'sourceId'='%s'
        AND a.allocation_role='participant' AND a.state='active'
    """ % (PARTICIPATION_OFFER,PARTICIPANT_PERSON,
           PARTICIPANT_MEMBERSHIP,PARTICIPATION_OFFER))=="1",
          "Third Person participation must trace the actual accepted offer")

    empty=permitted(api,key,other,READ,read_args(work=w))
    check(empty.get("workItemId")==w and empty.get("items")==[],
          "Accepted participant failed independently scoped empty Work read")
    note=permitted(api,key,owner,WRITE,
        write_args(ACTION_PARTICIPATION_OWNER,
                   "SYNTH_W07_PARTICIPATION_OWNER",work=w))
    view=permitted(api,key,other,READ,read_args(work=w))
    check(len(view.get("items") or [])==1
          and view["items"][0].get("commentId")==note.get("commentId")
          and view["items"][0].get("body")=="SYNTH_W07_PARTICIPATION_OWNER"
          and view["items"][0].get("authoredBySelf") is False,
          "Independently accepted Person could not read owner's original ink")
    response=permitted(api,key,other,WRITE,
        write_args(ACTION_PARTICIPATION_OTHER,
                   "SYNTH_W07_PARTICIPATION_OTHER",work=w))
    after=permitted(api,key,owner,READ,read_args(work=w))
    check(response.get("commentId")!=note.get("commentId")
          and response.get("body")=="SYNTH_W07_PARTICIPATION_OTHER"
          and any(item.get("commentId")==response.get("commentId")
                  and item.get("authoredBySelf") is False
                  for item in after.get("items",[])),
          "Native governor could not independently read accepted participant")
    forbidden(api,key,no_seat,READ,read_args(work=w),
              "unconnected fourth Person never inherits collaboration")

    # A linked occurrence's identity is a distinct gate. This probe uses
    # a synthetic occurrence reference ID: it tests the current disclosure
    # decision boundary, NOT original Event object creation/provenance.
    sql(db_url, """
      INSERT INTO atlas.work_item_context_links (
        id,organization_id,work_item_id,subject_domain,subject_kind,
        subject_id,relation_kind,created_by_membership_id,provenance
      ) VALUES (
        '%s'::uuid,'%s'::uuid,'%s'::uuid,'temporal','occurrence',
        '%s'::uuid,'for','%s'::uuid,
        '{"cloneFixture":true,"source":"synthetic_occurrence_disclosure_test"}'::jsonb
      )
    """ % (OCCURRENCE_LINK,ORG,w,OCCURRENCE_SUBJECT,OWNER_MEMBERSHIP))
    forbidden(api,key,other,READ,read_args(work=w),
              "accepted participant without linked occurrence identity must deny")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_OCCURRENCE_COMMENT,"undisclosed",work=w),
              "linked occurrence cannot leak through accepted Work write")
    check(len(permitted(api,key,owner,READ,read_args(work=w))["items"])==2,
          "Native Ledger governor retains original source during occurrence hold")

    def record_decision(source_action_id,decision):
        sql(db_url, """
          INSERT INTO atlas.subject_disclosure_decision_events_v1 (
            organization_id,ledger_id,target_person_id,subject_domain,
            subject_kind,subject_id,disclosure_class,decision_kind,
            source_action_id,reason,decided_by_person_id
          ) VALUES (
            '%s'::uuid,'%s'::uuid,'%s'::uuid,'event','occurrence',
            '%s'::uuid,'identity','%s','%s'::uuid,
            'Clone-only occurrence identity admission decision',
            '%s'::uuid
          )
        """ % (ORG,LEDGER,PARTICIPANT_PERSON,OCCURRENCE_SUBJECT,
               decision,source_action_id,OWNER_PERSON))

    record_decision(DISCLOSURE_GRANT_1,"grant")
    visible=permitted(api,key,other,READ,read_args(work=w))
    check(len(visible.get("items") or [])==2,
          "Signed occurrence identity grant did not restore Work read")
    added=permitted(api,key,other,WRITE,
          write_args(ACTION_OCCURRENCE_COMMENT,
                     "SYNTH_W07_OCCURRENCE_GATE_WRITTEN",work=w))
    check(added.get("commentId")
          and len(permitted(api,key,owner,READ,read_args(work=w))["items"])==3,
          "Signed linked-occurrence grant did not admit Work write")
    record_decision(DISCLOSURE_WITHHOLD,"withhold")
    forbidden(api,key,other,READ,read_args(work=w),
              "newest occurrence identity withhold must override old grant")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_OCCURRENCE_COMMENT,
                         "SYNTH_W07_OCCURRENCE_GATE_WRITTEN",work=w),
              "withheld occurrence must deny even saved-action replay")
    record_decision(DISCLOSURE_GRANT_2,"grant")
    check(len(permitted(api,key,other,READ,read_args(work=w))["items"])==3,
          "current occurrence identity regrant did not restore existing notes")
    print("PASS W07 signed synthetic occurrence reference deny/grant/withhold/regrant; "
          "real Event source provenance remains untested")

    # The next source is a *physically grounded* (synthetic) farm-zone-bed
    # relationship, distinct from the unsupported Event provenance case above.
    # Its guard must be satisfied by a signed governor and the actual Work
    # source Task, not by postulating a Work-to-bed identifier in test SQL.
    mark_stage("physical-source-preflight")
    check(sql(db_url, """
      SELECT count(*) FROM atlas.work_items w
      JOIN atlas.tasks t ON t.id=w.source_object_id
      JOIN atlas.farms f ON f.id=t.farm_id
      JOIN atlas.zones z ON z.id=t.zone_id AND z.farm_id=f.id
      JOIN atlas.growing_objects g ON g.farm_id=f.id AND g.zone_id=z.id
      WHERE w.id='%s'::uuid AND w.organization_id='%s'::uuid
        AND w.organization_unit_id=f.organization_unit_id
        AND w.source_object_type='legacy_task'
        AND w.stable_key='%s'
        AND g.id='%s'::uuid AND g.stable_key='%s'
        AND t.id='%s'::uuid AND f.id='%s'::uuid
    """ % (w,ORG,PHYSICAL_WORK_KEY,PHYSICAL_BED,PHYSICAL_BED_KEY,
           PHYSICAL_TASK,PHYSICAL_FARM)) == "1",
          "A real synthetic farm, matching Task, zone, bed and original Work source are mandatory")

    mark_stage("physical-crop-custody-signed-establish")
    status,custody=rpc(api,key,owner,
        "establish_farm_crop_ledger_custody_self_api_v1",{
          "p_farm_id":PHYSICAL_FARM,"p_ledger_id":LEDGER,
          "p_review":{"cropLedgerBoundaryReviewed":True,
                      "authorityDomain":"farm_crop_operations"}})
    check(status==200 and isinstance(custody,dict)
          and custody.get("ok") is True
          and custody.get("confersPersonAccess") is False
          and custody.get("created") is True,
          "Signed root must establish exact farm crop Ledger custody without Person grants")
    mark_stage("physical-governed-link-signed-establish")
    status,link=rpc(api,key,owner,
        "establish_work_growing_object_context_self_api_v1",{
          "p_ledger_id":LEDGER,"p_work_item_id":w,
          "p_object_id":PHYSICAL_BED,
          "p_review":{"humanConfirmed":True,
                      "reviewedWorkStableKey":PHYSICAL_WORK_KEY,
                      "reviewedObjectKey":PHYSICAL_BED_KEY}})
    check(status==200 and isinstance(link,dict)
          and link.get("ok") is True and link.get("created") is True
          and link.get("confersAccess") is False
          and link.get("workItemId")==w and link.get("contextId"),
          "Governor could not sign physically verified original Work-bed context")
    check(sql(db_url, """
      SELECT count(*) FROM atlas.work_item_context_links l
      JOIN atlas.work_items w ON w.id=l.work_item_id
      JOIN atlas.tasks t ON t.id=w.source_object_id
      JOIN atlas.growing_objects g ON g.id=l.subject_id
      JOIN atlas.farm_crop_ledger_custody_v1 c ON c.farm_id=g.farm_id
      WHERE l.id='%s'::uuid AND l.work_item_id='%s'::uuid
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND t.zone_id=g.zone_id AND t.farm_id=g.farm_id
        AND c.ledger_id='%s'::uuid AND c.custody_state='active'
        AND l.metadata->>'confersAccess'='false'
    """ % (link["contextId"],w,LEDGER)) == "1",
          "Signed physical source must retain exact Task-zone-farm-bed custody evidence")
    mark_stage("physical-no-disclosure-denial")
    forbidden(api,key,other,READ,read_args(work=w),
              "accepted participant denied physically linked undisclosed bed")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_PHYSICAL_COMMENT,"withheld bed",work=w),
              "undisclosed physical condition cannot leak in ordinary note")

    def physical_disclosure(action,category,decision):
        sql(db_url, """
          INSERT INTO atlas.subject_disclosure_decision_events_v1 (
            organization_id,ledger_id,target_person_id,
            subject_domain,subject_kind,subject_id,
            disclosure_class,decision_kind,source_action_id,reason,
            decided_by_person_id
          ) VALUES (
            '%s'::uuid,'%s'::uuid,'%s'::uuid,
            'spatial','growing_object','%s'::uuid,
            '%s','%s','%s'::uuid,
            'Clone-only independently reviewed source-bound physical disclosure',
            '%s'::uuid
          )
        """ % (ORG,LEDGER,PARTICIPANT_PERSON,PHYSICAL_BED,category,
               decision,action,OWNER_PERSON))

    mark_stage("physical-identity-only-denial")
    physical_disclosure(PHYSICAL_ID_GRANT,"identity","grant")
    forbidden(api,key,other,READ,read_args(work=w),
              "bed identity alone cannot disclose growing condition")
    mark_stage("physical-condition-grant-read-write")
    physical_disclosure(PHYSICAL_CONDITION_GRANT,"condition","grant")
    readable=permitted(api,key,other,READ,read_args(work=w))
    check(len(readable.get("items") or [])==3,
          "Both physical identity and condition required for existing Work read")
    physical_note=permitted(api,key,other,WRITE,
        write_args(ACTION_PHYSICAL_COMMENT,
                   "SYNTH_W07_PHYSICAL_SCOPE_NOTE",work=w))
    check(physical_note.get("commentId")
          and len(permitted(api,key,owner,READ,read_args(work=w))["items"])==4,
          "Independent participant physical disclosure did not admit signed read/write")

    mark_stage("physical-condition-withhold-denial")
    physical_disclosure(PHYSICAL_CONDITION_WITHHOLD,"condition","withhold")
    forbidden(api,key,other,READ,read_args(work=w),
              "withdrawn bed condition revokes all prior ordinary note read")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_PHYSICAL_COMMENT,
                         "SYNTH_W07_PHYSICAL_SCOPE_NOTE",work=w),
              "withdrawn condition also revokes saved-action replay")
    mark_stage("physical-condition-regrant-read")
    physical_disclosure(PHYSICAL_CONDITION_REGRANT,"condition","grant")
    restored=permitted(api,key,other,READ,read_args(work=w))
    check(len(restored.get("items") or [])==4,
          "Independent physical condition regrant must recover canonical history")
    print("PASS W07 signed farm/zone/Task/bed source plus independent identity "
          "and condition disclosure; withholding and regrant enforced")

    # Source withdrawal remains effective despite the membership/seat.
    sql(db_url, """
      UPDATE atlas.work_allocations SET state='released',
        released_at=now(),release_reason='clone:w07-participation-withdrawn'
      WHERE id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (PARTICIPANT_ALLOCATION,w))
    forbidden(api,key,other,READ,read_args(work=w),
              "revoked accepted participant loses historical note read")
    forbidden(api,key,other,WRITE,
              write_args(ACTION_PARTICIPATION_OTHER,
                         "SYNTH_W07_PARTICIPATION_OTHER",work=w),
              "revoked accepted participant cannot replay old note")
    check(len(permitted(api,key,owner,READ,read_args(work=w))["items"])==4,
          "Original Work retains participant's authorship after withdrawal")
    print("PASS W07 independently accepted third Person source-bound read/write, "
          "membership/offer-only denial, synthetic linked-occurrence identity "
          "disclosure and participant revocation")


def comment_side_effect_snapshot(db_url):
    """Compare source tables immediately around COMMENT RPCs only.

    Fixture membership, Work allocation, completion and independent disclosure
    setup are intentionally excluded; their own lawful records are unrelated.
    """
    return sql(db_url, """
        SELECT jsonb_build_object(
          'communication', (SELECT count(*) FROM atlas.communication_events),
          'outbound', (SELECT count(*) FROM atlas.communication_outbound_event_links),
          'communication_attention', (SELECT count(*) FROM atlas.communication_attention_events),
          'bell_receipts', (SELECT count(*) FROM atlas.bell_event_receipts),
          'attention', (SELECT count(*) FROM atlas.attention_events),
          'work_responsibility', (SELECT count(*) FROM atlas.event_work_responsibility_changes_v1),
          'occurrence_actions', (SELECT count(*) FROM atlas.ledger_occurrence_work_actions_v1),
          'work_results', (SELECT count(*) FROM atlas.work_execution_results),
          'result_acceptances', (SELECT count(*) FROM atlas.work_result_acceptances)
        )::text
    """)


def historical_completed_work_trial(db_url, api, key, owner, worker):
    """Root-governed original Work 901, no result-contract completion adapter.

    The disposable clone marks a synthetic no-contract original completed.
    This tests W07 reader/replay behavior, not genuine completion authorization
    or the separately governed accepted Work Result mechanics.
    """
    mark_stage("history-open-original-preflight")
    work = WRONG_WORK
    body = "SYNTH_W07_HISTORY_BEFORE_COMPLETE"
    check(sql(db_url, """
        SELECT count(*) FROM atlas.work_items
        WHERE id='%s'::uuid AND organization_id='%s'::uuid
          AND work_state='open' AND result_contract_key IS NULL
    """ % (work, ORG))=="1",
          "Historical test requires separate open original without Result contract")
    before_results = sql(db_url, "SELECT count(*) FROM atlas.work_execution_results")
    mark_stage("history-initial-signed-write")
    history_status,history_packet=rpc(
        api,key,owner,WRITE,write_args(ACTION_COMPLETED_SOURCE,body,work=work))
    if (history_status != 200 or not isinstance(history_packet,dict)
            or history_packet.get("ok") is not True):
        # Only fixed-format HTTP class and SQLSTATE are eligible to leave
        # the protected runner. Never surface message, detail, token or URL.
        safe_http = str(history_status) if history_status in (
            200,400,401,403,404,409,422,500,503) else "other"
        raw_sqlstate = (history_packet.get("code") if
                        isinstance(history_packet,dict) else None)
        safe_sqlstate = (raw_sqlstate if isinstance(raw_sqlstate,str)
                         and re.fullmatch(r"[0-9A-Z]{5}",raw_sqlstate)
                         else "none")
        mark_stage("history-initial-write-http-%s-sqlstate-%s" %
                   (safe_http,safe_sqlstate))
        check(False,"Historical original Work signed initial write failed")
    receipt=history_packet
    check(receipt.get("commentId") and receipt.get("idempotent") is False
          and receipt.get("isWorkResult") is False,
          "Pre-completion comment is not a canonical ordinary comment")
    comment_id=receipt["commentId"]
    check_read(permitted(api,key,owner,READ,read_args(work=work)),
               [comment_id],work=work)

    mark_stage("history-synthetic-completion-update")
    sql(db_url, """
        UPDATE atlas.work_items SET work_state='completed',completed_at=now()
        WHERE id='%s'::uuid AND organization_id='%s'::uuid
          AND work_state='open' AND result_contract_key IS NULL
    """ % (work,ORG))
    check(sql(db_url, """
        SELECT count(*) FROM atlas.work_items
        WHERE id='%s'::uuid AND organization_id='%s'::uuid
          AND work_state='completed'
    """ % (work, ORG))=="1",
          "Synthetic original completion transition not recorded")

    mark_stage("history-completed-signed-read")
    old=permitted(api,key,owner,READ,read_args(work=work))
    check_read(old,[comment_id],work=work)
    check(old["items"][0].get("body")==body,
          "Original Work comment disappeared when synthetic Work completed")
    mark_stage("history-completed-signed-replay")
    replay=permitted(api,key,owner,WRITE,
                     write_args(ACTION_COMPLETED_SOURCE,body,work=work))
    check(replay.get("commentId")==comment_id
          and replay.get("idempotent") is True,
          "Completing original Work must not erase original saved-action replay")
    mark_stage("history-completed-deny-new-write")
    status,packet=rpc(api,key,owner,WRITE,
                      write_args(ACTION_COMPLETED_NEW,
                                 "SYNTH_W07_NEW_AFTER_COMPLETE",work=work))
    check(status in (401,403) and isinstance(packet,dict)
          and packet.get("code")=="42501",
          "Completed original Work must reject a NEW signed comment")
    mark_stage("history-completed-unassigned-denial")
    forbidden(api,key,worker,READ,read_args(work=work),
              "unassigned worker cannot read closed other Work")
    mark_stage("history-completed-comment-count")
    check(sql(db_url, """
        SELECT count(*) FROM atlas.native_original_work_comments_v1
        WHERE organization_id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (ORG,work))=="1",
          "Completing original Work created duplicate or erased existing ink")
    check(sql(db_url,"SELECT count(*) FROM atlas.work_execution_results")==
          before_results,
          "Historical comment/replay created a Work Result")
    print("PASS W07 signed historical original Work read and exact replay; "
          "new append denied on completed no-contract Work")


def check_read(packet, expected_ids, work=WORK):
    check(packet.get("contractVersion") == "native_original_work_comments_v1"
          and packet.get("organizationId") == ORG
          and packet.get("ledgerId") == LEDGER
          and packet.get("workItemId") == work
          and packet.get("containsWorkResults") is False
          and packet.get("isNotificationInbox") is False
          and packet.get("authorsPreservedInCanonicalSource") is True
          and packet.get("authorIdentityDisclosure") == "self_boolean_only",
          "W07 read changed exact Work contract")
    rows = packet.get("items")
    check(isinstance(rows, list) and isinstance(packet.get("hasMore"), bool),
          "W07 read missing bounded list and cursor")
    check({x.get("commentId") for x in rows} == set(expected_ids)
          and len(rows) == len(expected_ids),
          "W07 signed read lost or duplicated original comment IDs")
    check(all(x.get("workItemId") == work and
              isinstance(x.get("authoredBySelf"), bool) and
              x.get("recordedAt") for x in rows),
          "W07 original read must include signed source timestamp / self flag")
    check("authorPersonId" not in json.dumps(rows)
          and "author_person_id" not in json.dumps(rows),
          "W07 reader leaked another Person's canonical identity")
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
        args.db_url)),
        "W07 REFUSES nonlocal database")
    api, key = c1.local_status()
    check(bool(re.match(r"^https?://(?:127[.]0[.]0[.]1|localhost):[0-9]+", api)),
          "W07 REFUSES nonlocal REST/GoTrue")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.work_items
        WHERE organization_id='%s'::uuid
        AND id='%s'::uuid AND work_state='open'
    """ % (ORG, WORK)) == "1",
          "Synthetic original Work must exist and be open")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.work_allocations
        WHERE id='%s'::uuid AND work_item_id='%s'::uuid
          AND assignee_canonical_person_id='%s'::uuid
          AND state='active'
          AND establishment_basis_kind='person_connection_receiver_uptake'
          AND establishment_basis->>'offerId'='%s'
          AND establishment_basis->>'uptakeKind'='recipient_self_accepted'
          AND establishment_basis->>'contractVersion'='exact_work_responsibility_establishment_v2'
    """ % (ALLOC, WORK, WORKER_PERSON, OFFER)) == "1",
          "Synthetic Work allocation must preserve exact governed receiver-uptake source")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.company_work_initial_responsibility_offers
        WHERE id='%s'::uuid
          AND work_item_id='%s'::uuid
          AND target_person_id='%s'::uuid
          AND offer_state='offered'
    """ % (OFFER,WORK,WORKER_PERSON)) == "1",
          "Exact synthetic original Work offer must exist")
    check(sql(args.db_url,
        "SELECT count(*) FROM atlas.native_original_work_comments_v1") == "0",
        "W07 local comments must begin empty")
    work_before = sql(args.db_url, "SELECT count(*) FROM atlas.work_items")
    results_before = sql(args.db_url,
                         "SELECT count(*) FROM atlas.work_execution_results")
    sessions = {}
    for label, expected in base.setup_auth(args.db_url):
        token, claims = c1.sign_in(api, key, label)
        check(claims.get("sub") == expected
              and claims.get("role") == "authenticated"
              and claims.get("session_id"),
              "W07 distinct signed identity failed: " + label)
        check(sql(args.db_url, """
             SELECT count(*) FROM auth.sessions
             WHERE id='%s'::uuid AND user_id='%s'::uuid
        """ % (claims["session_id"], expected)) == "1",
              "W07 live local session record absent: " + label)
        sessions[label] = token
    check(set(sessions) == {"owner", "worker", "outsider", "no-seat"},
          "W07 genuine four-session fixture incomplete")
    print("PASS W07 four distinct signed synthetic Auth sessions")

    owner = sessions["owner"]
    worker = sessions["worker"]
    outsider = sessions["outsider"]
    no_seat = sessions["no-seat"]
    check_read(permitted(api,key,owner,READ,read_args()), [])
    check_read(permitted(api,key,worker,READ,read_args()), [])
    for label,token in [("outsider",outsider),("no seat",no_seat)]:
        forbidden(api,key,token,READ,read_args(),label+" read")
        forbidden(api,key,token,WRITE,write_args(ACTION_OWNER,"unauthorized"),
                  label+" write")
    forbidden(api,key,worker,READ,read_args(WRONG_WORK), "wrong original Work")
    forbidden(api,key,worker,WRITE,
              write_args(ACTION_OWNER,"wrong original",WRONG_WORK),
              "worker cannot write unassigned Work")
    forbidden(api,key,owner,READ,read_args(WORK,OTHER_LEDGER),
              "native governor wrong Ledger read")
    forbidden(api,key,owner,WRITE,
              write_args(ACTION_OWNER,"wrong Ledger",WORK,OTHER_LEDGER),
              "native governor wrong Ledger write")
    forbidden(api,key,worker,READ,read_args(WORK,OTHER_LEDGER),
              "worker wrong Ledger read")
    forbidden(api,key,None,READ,read_args(),
              "unsigned anonymous read")
    forbidden(api,key,None,WRITE,write_args(ACTION_OWNER,"anonymous"),
              "unsigned anonymous write")

    mark_stage("notification-baseline-count")
    side_effect_baseline=comment_side_effect_snapshot(args.db_url)

    owner_receipt=permitted(api,key,owner,WRITE,
                            write_args(ACTION_OWNER,BODY_OWNER))
    check(owner_receipt.get("contractVersion")==
          "native_original_work_comment_write_v1"
          and owner_receipt.get("workItemId")==WORK
          and owner_receipt.get("ledgerId")==LEDGER
          and owner_receipt.get("body")==BODY_OWNER
          and owner_receipt.get("idempotent") is False
          and owner_receipt.get("originalWorkStateUnchanged") is True
          and owner_receipt.get("isWorkResult") is False
          and owner_receipt.get("notificationDelivered") is False,
          "Owner append was not canonical signed ordinary Work comment")
    owner_id=owner_receipt.get("commentId")
    check(owner_id and owner_receipt.get("recordedAt"),
          "Original comment identity and source time missing")

    other_view=permitted(api,key,worker,READ,read_args())
    worker_items=check_read(other_view,[owner_id])
    check(worker_items[0].get("body")==BODY_OWNER
          and worker_items[0].get("authoredBySelf") is False,
          "Responsible worker did not independently read owner's signed ink")

    worker_receipt=permitted(api,key,worker,WRITE,
                             write_args(ACTION_WORKER,BODY_WORKER))
    worker_id=worker_receipt.get("commentId")
    check(worker_id and worker_id!=owner_id
          and worker_receipt.get("body")==BODY_WORKER
          and worker_receipt.get("notificationDelivered") is False,
          "Worker ordinary note created no distinct canonical comment")
    owner_view=permitted(api,key,owner,READ,read_args())
    owner_rows=check_read(owner_view,[owner_id,worker_id])
    check({r.get("body") for r in owner_rows}=={BODY_OWNER,BODY_WORKER}
          and any(r.get("commentId")==worker_id and
                  r.get("authoredBySelf") is False for r in owner_rows),
          "Owner cannot independently read second authorized author's note")
    worker_view=permitted(api,key,worker,READ,read_args())
    check_read(worker_view,[owner_id,worker_id])
    check(any(r.get("commentId")==worker_id and
              r.get("authoredBySelf") is True
              for r in worker_view["items"]),
          "Worker must recognize their own original authored note")

    replay=permitted(api,key,owner,WRITE,
                     write_args(ACTION_OWNER,BODY_OWNER))
    check(replay.get("commentId")==owner_id
          and replay.get("idempotent") is True
          and replay.get("recordedAt")==owner_receipt.get("recordedAt"),
          "Same action retry lost its original signed receipt")
    conflict_status,conflict=rpc(api,key,owner,WRITE,
                   write_args(ACTION_OWNER,"SYNTH_DIFFERENT_BODY"))
    check(conflict_status==409 and isinstance(conflict,dict)
          and conflict.get("code")=="23505",
          "Same action ID attempted silent body overwrite")

    third=permitted(api,key,owner,WRITE,
                    write_args(ACTION_THIRD,BODY_THIRD))
    third_id=third.get("commentId")
    first_page=permitted(api,key,worker,READ,read_args(limit=2))
    check(first_page.get("hasMore") is True
          and first_page.get("nextRecordedAt")
          and first_page.get("nextCommentId"),
          "W07 bounded source-first page missing continuation")
    first_ids={r.get("commentId") for r in first_page["items"]}
    check(len(first_ids)==2, "W07 first page must contain exactly two")
    cursor=(first_page["nextRecordedAt"],first_page["nextCommentId"])
    second_page=permitted(api,key,worker,READ,
                          read_args(limit=2,after=cursor))
    check(second_page.get("hasMore") is False,
          "W07 last page cannot claim an unknown continuation")
    second_ids={r.get("commentId") for r in second_page["items"]}
    check(first_ids.isdisjoint(second_ids)
          and first_ids | second_ids=={owner_id,worker_id,third_id},
          "W07 cursor skipped or duplicated an original comment")

    invalid_status, invalid=rpc(api,key,owner,WRITE,
                                write_args(ACTION_OWNER," "))
    check(invalid_status in (400,422)
          and isinstance(invalid,dict)
          and invalid.get("code")=="22023",
          "Blank body must reject before new Work comment")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.native_original_work_comments_v1
        WHERE organization_id='%s'::uuid
          AND ledger_id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (ORG,LEDGER,WORK))=="3",
          "Three unique signed actions must create only three comments")

    # Actual concurrent requests: sequential retries alone are not evidence
    # of a unique action receipt under racing database transactions.
    mixed_bodies = ("SYNTH_W07_RACE_A_LOCAL_ONLY",
                    "SYNTH_W07_RACE_B_LOCAL_ONLY")
    mixed = simultaneous_writes(api, key, owner, ACTION_RACE_DIFFERENT,
                                mixed_bodies)
    check(sorted(status for status, _ in mixed) == [200, 409],
          "W07 concurrent different-body action must yield one save and one 23505")
    winner = next(payload for status, payload in mixed if status == 200)
    loser = next(payload for status, payload in mixed if status == 409)
    check(winner.get("ok") is True
          and winner.get("body") in mixed_bodies
          and winner.get("idempotent") is False
          and winner.get("commentId")
          and isinstance(loser, dict) and loser.get("code") == "23505",
          "W07 parallel differing bodies must retain one original immutable ink")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.native_original_work_comments_v1
        WHERE organization_id='%s'::uuid AND work_item_id='%s'::uuid
          AND author_person_id='%s'::uuid AND source_action_id='%s'::uuid
    """ % (ORG,WORK,OWNER_PERSON,ACTION_RACE_DIFFERENT)) == "1",
          "W07 concurrent different-body race duplicated the original action")

    same_body = "SYNTH_W07_RACE_REPLAY_LOCAL_ONLY"
    same = simultaneous_writes(api, key, owner, ACTION_RACE_IDENTICAL,
                               (same_body, same_body))
    check(all(status == 200 and isinstance(packet, dict)
              and packet.get("ok") is True and packet.get("body") == same_body
              for status, packet in same),
          "W07 parallel same-body action must both return canonical receipts")
    check(len({packet.get("commentId") for _, packet in same}) == 1
          and all(packet.get("commentId") for _, packet in same)
          and {packet.get("idempotent") for _, packet in same} == {True, False},
          "W07 concurrent replay must return one create, one replay and one ID")
    check(sql(args.db_url, """
        SELECT count(*) FROM atlas.native_original_work_comments_v1
        WHERE organization_id='%s'::uuid AND work_item_id='%s'::uuid
          AND author_person_id='%s'::uuid AND source_action_id='%s'::uuid
    """ % (ORG,WORK,OWNER_PERSON,ACTION_RACE_IDENTICAL)) == "1",
          "W07 concurrent replay duplicated the original action")
    mark_stage("notification-postcomment-count")
    check(comment_side_effect_snapshot(args.db_url)==side_effect_baseline,
          "Ordinary comment RPCs created notification, communication, Event or Work Result rows")
    print("PASS W07 no notification, communication, Event or Work Result table mutations")
    print("PASS W07 real simultaneous differing-body collision and same-body replay")

    # Revoke the synthetic worker's accepted responsibility. We do NOT
    # impersonate a real account or mutate the user's Production Work.
    sql(args.db_url, """
      UPDATE atlas.work_allocations SET state='released',
        released_at=now(),release_reason='clone:w07-access-withdrawn'
      WHERE id='%s'::uuid AND work_item_id='%s'::uuid
    """ % (ALLOC,WORK))
    forbidden(api,key,worker,READ,read_args(),
              "revoked worker must lose historical note read")
    forbidden(api,key,worker,WRITE,
              write_args(ACTION_WORKER,BODY_WORKER),
              "revoked worker must not recover replay without current read")
    check_read(permitted(api,key,owner,READ,read_args()),
               [owner_id,worker_id,third_id,
                winner["commentId"],same[0][1]["commentId"]])

    mark_stage("accepted-participant-regression")
    independently_accepted_participant_trial(
        args.db_url, api, key, owner, outsider, no_seat)
    historical_completed_work_trial(args.db_url, api, key, owner, worker)
    mark_stage("all-signed-cases-complete")

    check(sql(args.db_url,"SELECT count(*) FROM atlas.work_items")==
          work_before,"W07 comments manufactured another original Work")
    check(sql(args.db_url,
              "SELECT count(*) FROM atlas.work_execution_results")==
          results_before,"W07 ordinary comments manufactured a Work Result")
    check(sql(args.db_url, """
      SELECT count(*) FROM atlas.work_items
      WHERE id='%s'::uuid AND work_state='open'
    """ % WORK)=="1","W07 comments changed original Work state")
    print("PASS W07 real synthetic GoTrue signed governor/worker readback and "
          "source denial, exact Work/Ledger, immutable action replay, "
          "cursor paging, simultaneous idempotent race, revocation, "
          "no Work/Result/notification")
    Path(args.output).write_text(
      "PASS W07 signed local GoTrue 4 identities, exact Work read/write, "
      "cross-person refresh, original idempotent replay and collision denial, "
      "page cursor, parallel same-key same/different-body race, "
      "signed revocation, independent accepted participant, synthetic "
      "occurrence identity withhold/grant/regrant, historical original Work "
      "replay/read and new-write denial, signed farm/zone/Task/bed physical "
      "disclosure identity and condition withhold/regrant, "
      "no notification/Event table mutation, "
      "no new Work or Work Result\n",
      encoding="utf-8"
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        # No raw SQL, database URL, JWT, response payload or exception message.
        import sys
        if "--output" in sys.argv:
            i = sys.argv.index("--output")
            if i + 1 < len(sys.argv):
                Path(sys.argv[i + 1]).write_text(
                    "FAILED W07 signed disposable clone stage: %s; class: %s\n"
                    % (W07_STAGE, type(exc).__name__), encoding="utf-8"
                )
        raise
