#!/usr/bin/env python3
"""Optional exact source proof when candidate includes held historical review.
Caller provides independent real local GoTrue sessions, already verified by
the trusted disposable C1 runner. NEVER invoke against a live database.
"""
from pathlib import Path

ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
OWNER="e5200000-0000-4000-8000-000000000101"
PERSON="e5200000-0000-4000-8000-000000000102"
WORK="ec400000-0000-4000-8000-000000000901"
ALLOC="ec400000-0000-4000-8000-000000000301"
LEGACY="ec400000-0000-4000-8000-000000000201"
def a(n): return f"ec400000-0000-4000-8000-{n:012x}"

def proof(db,api,key,tokens,h):
    check,sql,literal,allow,deny,rpc=h.check,h.sql,h.literal,h.allow,h.deny,h.rpc
    owner=tokens["owner"];worker=tokens["worker"]
    outsider=tokens["outsider"];no_seat=tokens["no-seat"]
    sig=("public.governor_link_historical_self_adoption_self_api_v1"
         "(uuid,uuid,uuid,uuid,uuid,uuid)")
    check(sql(db,"select to_regprocedure("+literal(sig)+") is not null")=="t",
          "Required historical native source not installed")
    # Existing trust fixture has native Person, Ledger and local JWTs. Add
    # deliberately ACTIVE obsolete membership, never a present-day grant.
    seed=f"""
    INSERT INTO atlas.organization_memberships(
     id,organization_id,user_id,role,active,person_id)
    VALUES ('{LEGACY}'::uuid,'{ORG}'::uuid,
     'e5200000-0000-4000-8000-000000000002'::uuid,
     'member',true,'{PERSON}'::uuid);
    INSERT INTO atlas.work_items(
     id,organization_id,title,work_state,source_object_type,source_object_id,stable_key)
    VALUES ('{WORK}'::uuid,'{ORG}'::uuid,
     'Fictional archival self-adopted duty','open',
     'legacy_task_slice','ec400000-0000-4000-8000-000000000902'::uuid,
     'clone:historic-self-adoption');
    INSERT INTO atlas.work_allocations(
     id,organization_id,work_item_id,assignee_membership_id,
     allocation_role,state,establishment_basis_kind,establishment_basis)
    VALUES('{ALLOC}'::uuid,'{ORG}'::uuid,'{WORK}'::uuid,'{LEGACY}'::uuid,
     'responsible','active','self_adoption','{{"historical":true}}'::jsonb);
    INSERT INTO atlas.company_work_native_ledger_relevance(
     organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
     attestation_source_ref,attestation_reason,established_by_person_id)
    VALUES('{ORG}'::uuid,'{WORK}'::uuid,'{LEDGER}'::uuid,
     'serves_purpose','owner_attested','clone:historical-reviewed',
     'Fictional original Work context for signed native review','{OWNER}'::uuid);
    """
    # Deliberately fictional SQL can run only in a disposable local clone.
    check(sql(db,"select current_database()")=="postgres","Not disposable postgres")
    check(sql(db,"select count(*) from auth.users where id="
              "'e5200000-0000-4000-8000-000000000002'::uuid")=="1",
          "C1 fictional worker absent")
    h.c1.sql(db,seed)
    base_count=sql(db,"select count(*) from atlas.work_items")
    original=lambda expr:sql(db,expr+" where work_item_id="+literal(WORK)+"::uuid")
    link=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
       p_work_item_id=WORK,p_allocation_id=ALLOC,p_related_person_id=PERSON,
       p_action_id=a(401))
    deny(api,key,worker,"governor_link_historical_self_adoption_self_api_v1",
         link,"Old worker membership cannot authorize Person reconciliation")
    deny(api,key,outsider,"governor_link_historical_self_adoption_self_api_v1",
         link,"Outsider cannot govern historical Person reconciliation")
    receipt=allow(api,key,owner,"governor_link_historical_self_adoption_self_api_v1",link)
    lid=receipt.get("linkId")
    check(lid and receipt.get("historicalOnly") is True
         and receipt.get("newWorkCreated") is False
         and receipt.get("newAuthorityGranted") is False,
         "Owner Person link created current authority")
    again=allow(api,key,owner,"governor_link_historical_self_adoption_self_api_v1",link)
    check(again.get("replay") is True and again.get("linkId")==lid,
          "Historical Person review action not idempotent")
    pending=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
       p_link_id=lid,p_evidence_text="Fictional earlier duty completion is recalled, not asserted as a fresh physical Actual.",
       p_action_id=a(402))
    deny(api,key,outsider,"report_historical_self_adoption_pending_self_api_v1",
         pending,"Wrong Person cannot report linked historical evidence")
    deny(api,key,no_seat,"report_historical_self_adoption_pending_self_api_v1",
         pending,"No-seat Person cannot submit historical Work evidence")
    worker_report=allow(api,key,worker,
         "report_historical_self_adoption_pending_self_api_v1",pending)
    eid=worker_report.get("evidenceId")
    check(eid and worker_report.get("state")=="pending"
      and worker_report.get("acceptedDone") is False,
      "Worker historical report falsely accepted Done")
    r2=allow(api,key,worker,"report_historical_self_adoption_pending_self_api_v1",pending)
    check(r2.get("replay") is True and r2.get("evidenceId")==eid,
          "Worker historical report replay duplicated source evidence")
    wrong=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_link_id=lid,p_outcome="historically_performed",
      p_evidence_id=eid,p_action_id=a(403))
    deny(api,key,worker,"governor_review_historical_self_adoption_self_api_v1",
      wrong,"Worker cannot accept own historical evidence")
    deny(api,key,outsider,"governor_review_historical_self_adoption_self_api_v1",
      wrong,"Unconnected Person cannot review historical performance")
    read=dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_work_item_id=WORK)
    deny(api,key,worker,"governor_historical_self_adoption_history_self_api_v1",
      read,"Worker cannot read governor-only historical review stream")
    owner_view=allow(api,key,owner,
         "governor_historical_self_adoption_history_self_api_v1",read)
    check(owner_view.get("historicalOnly") is True
          and len(owner_view.get("items",[]))==2
          and owner_view.get("hasMore") is False,
          "Governor signed history before decision lacks exact two original events")
    # An active old membership must not pass the retired original Done API,
    # even though the exact worker is authenticated and had historical work.
    h.signed_source(db,worker,(
       "atlas.report_self_responsible_company_work_self_api_v1("
       +literal(WORK)+"::uuid,'completed'::text,'clone:legacy-denied'::text,"
       "'{}'::jsonb)"),"42501")
    # Current connection withdrawal immediately removes pending authority.
    sql(db,"update ledger.seats set seat_state='ended',ended_at=now() "
        "where ledger_id="+literal(LEDGER)+"::uuid "
        "and person_entity_id="+literal(PERSON)+"::uuid")
    deny(api,key,worker,"report_historical_self_adoption_pending_self_api_v1",
      dict(pending,p_action_id=a(404)),
      "Old membership cannot bypass revoked native Person Seat")
    # Owner can still adjudicate existing historic evidence, without a
    # second Work, a Work state change, or a fabricated accepted Result.
    outcome=allow(api,key,owner,"governor_review_historical_self_adoption_self_api_v1",wrong)
    check(outcome.get("outcome")=="historically_performed"
      and outcome.get("workStateChanged") is False,
      "Governor historical acceptance was mistaken for a new Done")
    again=allow(api,key,owner,"governor_review_historical_self_adoption_self_api_v1",wrong)
    check(again.get("replay") is True and again.get("reviewId")==outcome.get("reviewId"),
      "Governor history review replay changed event identity")
    check(sql(db,"select count(*) from atlas.work_items")==base_count,
          "Historical evidence generated new original Work")
    check(sql(db,"select work_state from atlas.work_items where id="+literal(WORK)+"::uuid")=="open",
          "Historical assessment silently closed original Work")
    check(original("select count(*) from atlas.work_execution_results")=="0"
      and original("select count(*) from atlas.work_result_acceptances")=="0"
      and original("select count(*) from atlas.work_lifecycle_events_v1")=="0",
      "Historical report forged an accepted Result, Actual or lifecycle Done")
    print("PASS signed native historical Person link, pending evidence, owner disposition, "
          "old membership denial, current Seat revocation and immutable Work/Result history")
    return "PASS signed historical review: governor / worker / outsider / no-seat, replay, "
           "old membership deny, revoked Seat, original Work/Result preserved.\n"
