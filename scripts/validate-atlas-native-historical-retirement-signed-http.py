#!/usr/bin/env python3
"""HELD companion signed retirement proof for the existing C1 disposable clone.

Invoke with the SAME trusted independent local GoTrue sessions and transport
helpers as validate-atlas-historical-self-adoption-signed-http.py. This is not
yet called by the protected main runner; do not mark signed retirement proven
until it is attached to an owner-reviewed, protected test carrier and passes.
Never run against live/production SQL.
"""

ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
OWNER="e5200000-0000-4000-8000-000000000101"
PERSON="e5200000-0000-4000-8000-000000000102"
WORK="ec410000-0000-4000-8000-000000000901"
ALLOC="ec410000-0000-4000-8000-000000000301"
LEGACY="ec400000-0000-4000-8000-000000000201"

def action(n):
    return f"ec410000-0000-4000-8000-{n:012x}"

def proof(db, api, key, tokens, h):
    check,sql,literal,allow,deny=h.check,h.sql,h.literal,h.allow,h.deny
    owner=tokens["owner"]
    worker=tokens["worker"]
    outsider=tokens["outsider"]
    no_seat=tokens["no-seat"]
    for name in (
      "public.governor_retire_historical_work_self_api_v1(uuid,uuid,uuid,text,uuid)",
      "public.governor_historical_retirement_preflight_self_api_v1(uuid,uuid,uuid)"
    ):
        check(sql(db,"select to_regprocedure("+literal(name)+") is not null")=="t",
              "Exact retirement RPC unavailable in clone: "+name)

    # Only fictional tenant and users. Do not run with real Org/Person IDs.
    check(sql(db,"select current_database()")=="postgres",
          "Refusing a non-disposable database")
    check(sql(db,"select count(*) from auth.users where id="
          "'e5200000-0000-4000-8000-000000000002'::uuid")=="1",
          "Fictional C1 worker not found")
    seed=f"""
      INSERT INTO atlas.organization_memberships(
       id,organization_id,user_id,role,active,person_id)
      VALUES('{LEGACY}'::uuid,'{ORG}'::uuid,
       'e5200000-0000-4000-8000-000000000002'::uuid,
       'member',true,'{PERSON}'::uuid);
      INSERT INTO atlas.work_items(
       id,organization_id,title,work_state,source_object_type,
       source_object_id,stable_key)
      VALUES('{WORK}'::uuid,'{ORG}'::uuid,'Fictional obsolete archived duty',
       'open','legacy_task_slice',
       'ec410000-0000-4000-8000-000000000902'::uuid,
       'clone:historical-retirement-proof');
      INSERT INTO atlas.work_allocations(
       id,organization_id,work_item_id,assignee_membership_id,
       assigned_by_membership_id,allocation_role,state,
       establishment_basis_kind,establishment_basis)
      VALUES('{ALLOC}'::uuid,'{ORG}'::uuid,'{WORK}'::uuid,'{LEGACY}'::uuid,
       '{LEGACY}'::uuid,'responsible','active','self_adoption',
       jsonb_build_object(
        'contractVersion','exact_work_responsibility_establishment_v2',
        'basisKind','self_adoption','organizationId','{ORG}',
        'workItemId','{WORK}','actorMembershipId','{LEGACY}',
        'assigneeMembershipId','{LEGACY}',
        'sourceKind','legacy_task_slice',
        'sourceId','ec410000-0000-4000-8000-000000000902'));
      INSERT INTO atlas.company_work_native_ledger_relevance(
       organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
       attestation_source_ref,attestation_reason,established_by_person_id)
      VALUES('{ORG}'::uuid,'{WORK}'::uuid,'{LEDGER}'::uuid,
       'serves_purpose','owner_attested','clone:obsolete-review',
       'Fictional original Work context for retirement review','{OWNER}'::uuid);
    """
    # Preserve PostgreSQL's original error (not the SQL command or DB URL)
    # when the strictly fictional fixture is rejected by real source guards.
    # The shared C1 helper captures stderr but CalledProcessError.__str__
    # otherwise suppresses it, making a signed proof failure uninterpretable.
    try:
        h.c1.sql(db,seed)
    except Exception as exc:
        import subprocess
        if not isinstance(exc,subprocess.CalledProcessError):
            raise
        detail=(exc.stderr or "").strip()[-1200:]
        raise AssertionError("Fictional retirement seed rejected by PostgreSQL: "+
                             detail) from None
    original=lambda table:sql(db,(
      "select count(*) from "+table+" where work_item_id="+literal(WORK)+"::uuid"))
    result_before=original("atlas.work_execution_results")
    accepted_before=original("atlas.work_result_acceptances")
    original_count=sql(db,"select count(*) from atlas.work_items")
    link=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_work_item_id=WORK,p_allocation_id=ALLOC,
      p_related_person_id=PERSON,p_action_id=action(1))
    deny(api,key,worker,"governor_link_historical_self_adoption_self_api_v1",
      link,"Historical membership is not current Person confirmation authority")
    receipt=allow(api,key,owner,"governor_link_historical_self_adoption_self_api_v1",link)
    link_id=receipt.get("linkId")
    check(bool(link_id),"No immutable governor link")
    review=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
      p_link_id=link_id,p_outcome="obsolete_cancelled",
      p_evidence_id=None,p_action_id=action(2))
    deny(api,key,worker,"governor_review_historical_self_adoption_self_api_v1",
      review,"Worker cannot review obsolete historic Work")
    decided=allow(api,key,owner,"governor_review_historical_self_adoption_self_api_v1",
      review)
    review_id=decided.get("reviewId")
    check(bool(review_id) and decided.get("workStateChanged") is False,
      "A review must not itself cancel original Work")
    preflight=dict(p_organization_id=ORG,p_ledger_id=LEDGER,p_review_id=review_id)
    deny(api,key,worker,"governor_historical_retirement_preflight_self_api_v1",
      preflight,"Worker cannot see governor dependency snapshot")
    deny(api,key,outsider,"governor_historical_retirement_preflight_self_api_v1",
      preflight,"Outsider cannot see governor dependency snapshot")
    deny(api,key,no_seat,"governor_historical_retirement_preflight_self_api_v1",
      preflight,"No-seat Person cannot read retirement dependencies")
    impact=allow(api,key,owner,"governor_historical_retirement_preflight_self_api_v1",
      preflight)
    check(impact.get("retirable") is True and impact.get("blockingDependencyCount")==0
      and len(impact.get("impactToken",""))==32,
      "Obsolete original without dependencies did not pass preflight")
    final=dict(preflight,p_impact_token=impact["impactToken"],p_action_id=action(3))
    deny(api,key,worker,"governor_retire_historical_work_self_api_v1",
      final,"Worker cannot cancel reviewed original")
    deny(api,key,outsider,"governor_retire_historical_work_self_api_v1",
      final,"Outsider cannot cancel reviewed original")
    deny(api,key,owner,"governor_retire_historical_work_self_api_v1",
      dict(final,p_impact_token="0"*32),
      "Stale dependency snapshot must not cancel Work")
    prior=sql(db,"select count(*) from atlas.work_lifecycle_events_v1 "
      "where work_item_id="+literal(WORK)+"::uuid "
      "and event_kind='work_transition_applied'")
    retired=allow(api,key,owner,"governor_retire_historical_work_self_api_v1",final)
    check(retired.get("workState")=="cancelled"
      and retired.get("historicalReviewId")==review_id
      and retired.get("idempotent") is False
      and retired.get("originalResultId") is None
      and retired.get("acceptedEvidenceId") is None,
      "Retirement must be cancellation, never a fabricated Done")
    replay=allow(api,key,owner,"governor_retire_historical_work_self_api_v1",final)
    check(replay.get("idempotent") is True
      and replay.get("eventId")==retired.get("eventId"),
      "Retirement action replay minted a second terminal event")
    deny(api,key,owner,"governor_retire_historical_work_self_api_v1",
      dict(final,p_action_id=action(4)),
      "A second action may not retire the same original again")
    check(sql(db,"select work_state from atlas.work_items where id="
      +literal(WORK)+"::uuid")=="cancelled",
      "Original did not project cancelled state")
    check(sql(db,"select count(*) from atlas.work_lifecycle_events_v1 "
      "where work_item_id="+literal(WORK)+"::uuid "
      "and event_kind='work_transition_applied'")==str(int(prior)+1),
      "The original received duplicate terminal transitions")
    check(sql(db,"select state from atlas.work_allocations where id="
      +literal(ALLOC)+"::uuid")=="released",
      "Reviewed old responsibility was not released")
    check(original("atlas.work_execution_results")==result_before
      and original("atlas.work_result_acceptances")==accepted_before
      and sql(db,"select count(*) from atlas.work_items")==original_count,
      "Retirement forged a physical Result, Acceptance or new Work")
    return ("PASS genuine signed governor historic retirement: worker/outsider/no-seat "
            "denials, token freshness, single cancel, replay, no fabricated Done.\n")
