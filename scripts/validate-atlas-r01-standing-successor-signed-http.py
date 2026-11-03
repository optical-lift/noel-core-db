#!/usr/bin/env python3
"""R01 two-Subject governor -> signed physical Actual -> successor gate.

Called only from the existing protected full-schema disposable Supabase clone
after the pre-existing signed care regressions. It receives actual independent
GoTrue bearer tokens from that validator. No real Elm data, local RiverSong
retained-clone writes, production database URL, or source grants are permitted.
A missing public RPC is FAILURE, not a successful authorization denial.
"""
from datetime import date, timedelta
import re

ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
FARM="e5200000-0000-4000-8000-000000000b01"
BED4="e5200000-0000-4000-8000-000000000b04"
BED5="e5200000-0000-4000-8000-000000000b05"
STATE4="ec400000-0000-4000-8000-000000000003"
STATE5="ec500000-0000-4000-8000-000000000003"
CAMPAIGN="ec400000-0000-4000-8000-000000000010"
PARTIAL="ec400000-0000-4000-8000-000000000011"
FULL="ec400000-0000-4000-8000-000000000012"
OWNER_RPC="owner_establish_standing_continuing_care_work_self_api_v1"
OWNER_SIG=("public.owner_establish_standing_continuing_care_work_self_api_v1"
           "(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])")
PRIVATE_SIG=("atlas.owner_establish_standing_continuing_care_work_self_api_v1"
             "(uuid,uuid,uuid,uuid,text,date,date,uuid,smallint[])")

def require(ok,message):
    if not ok: raise AssertionError("R01 signed successor: "+message)

def literal(value):
    return "'"+str(value).replace("'","''")+"'"

def seed_two_subjects(care,db):
    # No fixture DDL. Both Subjects, physical Need bindings, and two different
    # cadence rules derive from the previously proven fictional Bed 3 shapes.
    # BEGIN/COMMIT is on the disposable clone, never an installed database.
    q="""
BEGIN;
DO $r01_clone_fixture$
BEGIN
 IF current_database()<>'postgres' OR inet_server_addr() IS NULL
   OR (SELECT count(*) FROM atlas.growing_objects WHERE id IN
      ('e5200000-0000-4000-8000-000000000b04'::uuid,
       'e5200000-0000-4000-8000-000000000b05'::uuid))<>2
   OR (SELECT count(*) FROM atlas.rhythm_state WHERE id IN
      ('ec400000-0000-4000-8000-000000000003'::uuid,
       'ec500000-0000-4000-8000-000000000003'::uuid))<>0
   OR (SELECT count(*) FROM atlas.rhythm_rules WHERE
       id='ec300000-0000-4000-8000-000000000001'::uuid)<>1
 THEN RAISE EXCEPTION 'R01 fictional two-Subject canary missing or duplicated'; END IF;
END;
$r01_clone_fixture$;
INSERT INTO atlas.rhythm_rules(
 id,organization_id,farm_id,rule_key,rhythm_key,version,label,status,
 applicability,validity_interval_seconds,warning_window_seconds,
 grace_window_seconds,qualifying_touches,failure_consequence,player_routing,metadata
)
SELECT x.id::uuid,r.organization_id,r.farm_id,x.k,r.rhythm_key,r.version,
 x.label,r.status,r.applicability,x.seconds,r.warning_window_seconds,
 r.grace_window_seconds,r.qualifying_touches,r.failure_consequence,
 r.player_routing,r.metadata
FROM atlas.rhythm_rules r
CROSS JOIN (VALUES
 ('ec400000-0000-4000-8000-000000000001','r01-signed-bed4',
  'Fictional Bed 4 stewardship',345600),
 ('ec500000-0000-4000-8000-000000000001','r01-signed-bed5',
  'Fictional Bed 5 stewardship',172800)
) AS x(id,k,label,seconds)
WHERE r.id='ec300000-0000-4000-8000-000000000001'::uuid;
INSERT INTO atlas.rhythm_bindings(
 id,organization_id,farm_id,rhythm_rule_id,binding_key,inheritance_layer,
 subject_kind,subject_id,priority,active,metadata
)
SELECT x.id::uuid,b.organization_id,b.farm_id,x.rule_id::uuid,x.key,
 b.inheritance_layer,b.subject_kind,x.bed_id::uuid,b.priority,b.active,b.metadata
FROM atlas.rhythm_bindings b
CROSS JOIN (VALUES
 ('ec400000-0000-4000-8000-000000000002','ec400000-0000-4000-8000-000000000001',
  'e5200000-0000-4000-8000-000000000b04','r01-bed4'),
 ('ec500000-0000-4000-8000-000000000002','ec500000-0000-4000-8000-000000000001',
  'e5200000-0000-4000-8000-000000000b05','r01-bed5')
) AS x(id,rule_id,bed_id,key)
WHERE b.id='ec300000-0000-4000-8000-000000000002'::uuid;
INSERT INTO atlas.rhythm_state(
 id,organization_id,farm_id,rhythm_binding_id,rhythm_rule_id,rhythm_key,
 subject_kind,subject_id,state,effective_rule_version,visibility_scope,
 state_reason,metadata
)
SELECT x.id::uuid,s.organization_id,s.farm_id,x.binding_id::uuid,
 x.rule_id::uuid,s.rhythm_key,s.subject_kind,x.bed_id::uuid,
 'due',s.effective_rule_version,s.visibility_scope,
 '{"source":"r01_disposable_two_subject_signed_gate"}'::jsonb,s.metadata
FROM atlas.rhythm_state s
CROSS JOIN (VALUES
 ('ec400000-0000-4000-8000-000000000003','ec400000-0000-4000-8000-000000000002',
  'ec400000-0000-4000-8000-000000000001','e5200000-0000-4000-8000-000000000b04'),
 ('ec500000-0000-4000-8000-000000000003','ec500000-0000-4000-8000-000000000002',
  'ec500000-0000-4000-8000-000000000001','e5200000-0000-4000-8000-000000000b05')
) AS x(id,binding_id,rule_id,bed_id)
WHERE s.id='ec300000-0000-4000-8000-000000000003'::uuid;
UPDATE atlas.rhythm_state
 SET warning_at=now()-interval '2 days',
     due_at=now()-interval '1 day'
 WHERE id IN ('ec400000-0000-4000-8000-000000000003'::uuid,
              'ec500000-0000-4000-8000-000000000003'::uuid);
INSERT INTO atlas.weed_cards(
 id,farm_id,object_id,card_key,current_condition,target_condition,metadata
)
SELECT x.id::uuid,w.farm_id,x.bed_id::uuid,x.k,w.current_condition,
 w.target_condition,w.metadata
FROM atlas.weed_cards w
CROSS JOIN (VALUES
 ('ec400000-0000-4000-8000-000000000004',
  'e5200000-0000-4000-8000-000000000b04','r01-weed-bed4'),
 ('ec500000-0000-4000-8000-000000000004',
  'e5200000-0000-4000-8000-000000000b05','r01-weed-bed5')
) AS x(id,bed_id,k)
WHERE w.id='ec300000-0000-4000-8000-000000000004'::uuid;
DO $r01_seed_post$
BEGIN
 IF (SELECT count(*) FROM atlas.rhythm_state WHERE id IN
      ('ec400000-0000-4000-8000-000000000003'::uuid,
       'ec500000-0000-4000-8000-000000000003'::uuid))<>2
 OR (SELECT count(DISTINCT validity_interval_seconds)
     FROM atlas.rhythm_rules WHERE id IN
      ('ec400000-0000-4000-8000-000000000001'::uuid,
       'ec500000-0000-4000-8000-000000000001'::uuid))<>2
 OR (SELECT count(*) FROM atlas.work_items WHERE source_object_id IN
      ('ec400000-0000-4000-8000-000000000003'::uuid,
       'ec500000-0000-4000-8000-000000000003'::uuid))<>0
 THEN RAISE EXCEPTION 'R01 two independent cadence Subjects not seeded safely'; END IF;
END;
$r01_seed_post$;
COMMIT;
"""
    care.sql(db,q)
    print("PASS R01 fictional Bed 4 and Bed 5 independent cadence rules; no Work precreated")

def proof(db,api,key,tokens,scope,care):
    require(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",db)),
        "only existing disposable Supabase PostgreSQL allowed")
    owner,worker,outsider=tokens["owner"],tokens["worker"],tokens["outsider"]
    for signature,allowed in ((OWNER_SIG,"t"),(PRIVATE_SIG,"f")):
        require(care.sql(db,"select to_regprocedure("+literal(signature)+") is not null")=="t",
                "required owner source absent: "+signature)
        require(care.sql(db,"select has_function_privilege('authenticated',"
               +literal(signature)+",'EXECUTE')")==allowed,
                "owner source transport ACL incorrect")
    require(care.sql(db,"select has_function_privilege('anon',"
            +literal(OWNER_SIG)+",'EXECUTE')")=="f",
            "anon must never call owner source")
    seed_two_subjects(care,db)
    for bed,base_action in ((BED4,41),(BED5,43)):
        for field,i in (("identity",0),("condition",1)):
            data=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
                p_target_person_id="e5200000-0000-4000-8000-000000000102",
                p_subject_domain="spatial",p_subject_kind="growing_object",
                p_subject_id=bed,p_disclosure_class=field,
                p_decision_kind="grant",
                p_source_action_id=f"ec400000-0000-4000-8000-0000000000{base_action+i}",
                p_reason="Exact fictional governed seasonal visit subject information.")
            care.allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",data)
    service=care.sql(db,"select (now() at time zone 'America/Chicago')::date")
    require(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}",service)),"no governed service date")
    end=(date.fromisoformat(service)+timedelta(days=10)).isoformat()
    isodow=int(care.sql(db,"select extract(isodow from "+literal(service)+"::date)::integer"))
    wrong_weekday=1 if isodow!=1 else 2
    args=dict(p_organization_id=ORG,p_ledger_id=LEDGER,
       p_rhythm_state_id=STATE4,p_scope_id=scope,
       p_visit_reason="Fictional governor approved bounded Bed 4 and Bed 5 winter visits.",
       p_service_date=service,p_campaign_end_date=end,p_action_id=CAMPAIGN,
       p_workdays_iso=[1,2,3,4,5,6,7])
    care.deny(api,key,worker,OWNER_RPC,args,"Worker cannot approve own standing visit")
    care.deny(api,key,outsider,OWNER_RPC,args,"Outsider cannot approve standing visit")
    invalid=dict(args,p_workdays_iso=[wrong_weekday])
    status,obj=care.rpc(api,key,owner,OWNER_RPC,invalid)
    require(status==400 and isinstance(obj,dict) and obj.get("code")=="22023",
            "governor's disallowed initial workday must fail at source; not PGRST202")
    # When the held R02 universal transport is installed, it must establish
    # the FIRST original using genuine signed governor authority. The prior
    # specialized owner writer must then return exactly the same source action.
    generic_sig=("public.governor_approve_rhythm_opportunity_self_api_v1"
                 "(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)")
    generic=care.sql(db,"select to_regprocedure("+literal(generic_sig)+") is not null")=="t"
    if generic:
        review_args={"p_organization_id":ORG,"p_ledger_id":LEDGER,
                     "p_scope_id":scope,"p_limit":20,"p_after_candidate_id":None}
        care.deny(api,key,worker,"governor_review_rhythm_opportunities_self_api_v1",
                  review_args,"worker cannot preview governor rhythm opportunities")
        care.deny(api,key,outsider,"governor_review_rhythm_opportunities_self_api_v1",
                  review_args,"outsider cannot preview governor rhythm opportunities")
        preview=care.allow(api,key,owner,
            "governor_review_rhythm_opportunities_self_api_v1",review_args)
        require(preview.get("contractVersion")=="governed_rhythm_opportunities_v1"
          and preview.get("coverage")=="registered_source_adapters_only"
          and preview.get("notAnAllRhythmsCensus") is True
          and preview.get("workerPersonId")=="e5200000-0000-4000-8000-000000000102"
          and isinstance(preview.get("items"),list)
          and any(item.get("candidateId")==STATE4 and item.get("canOffer") is True
                  and item.get("adapterKey")=="continuing_care_actual_v1"
                  and item.get("physicalConditionAsserted") is False
                  for item in preview["items"]),
          "universal source preview lacks real eligible Subject or exact coverage")
        gargs={"p_organization_id":ORG,"p_ledger_id":LEDGER,
               "p_scope_id":scope,"p_adapter_key":"continuing_care_actual_v1",
               "p_candidate_id":STATE4,"p_reason":args["p_visit_reason"],
               "p_first_workday":service,"p_campaign_end_date":end,
               "p_approved_iso_workdays":[1,2,3,4,5,6,7],"p_action_id":CAMPAIGN}
        care.deny(api,key,worker,"governor_approve_rhythm_opportunity_self_api_v1",
                  gargs,"worker cannot approve universal rhythm mandate")
        care.deny(api,key,outsider,"governor_approve_rhythm_opportunity_self_api_v1",
                  gargs,"outsider cannot approve universal rhythm mandate")
        code,obj=care.rpc(api,key,owner,
           "governor_approve_rhythm_opportunity_self_api_v1",
           dict(gargs,p_adapter_key="unsupported_other_rhythm_v1"))
        require(code==400 and isinstance(obj,dict) and obj.get("code")=="22023",
                "unregistered source adapter was not rejected")
        code,obj=care.rpc(api,key,owner,
           "governor_approve_rhythm_opportunity_self_api_v1",
           dict(gargs,p_approved_iso_workdays=[wrong_weekday]))
        require(code==400 and isinstance(obj,dict) and obj.get("code")=="22023",
                "governor approved a weekday outside the selected mandate")
        first=care.allow(api,key,owner,
            "governor_approve_rhythm_opportunity_self_api_v1",gargs)
        require(first.get("contractVersion")=="governed_rhythm_approval_v1"
          and first.get("newOriginalWorkCreated") is True
          and first.get("adapterKey")=="continuing_care_actual_v1"
          and first.get("candidateId")==STATE4
          and first.get("actionId")==CAMPAIGN
          and first.get("noPhysicalResultInferred") is True,
          "universal approval did not verify the first original and source")
        repeat_generic=care.allow(api,key,owner,
            "governor_approve_rhythm_opportunity_self_api_v1",gargs)
        require(repeat_generic.get("existingAction") is True
          and repeat_generic.get("workItemId")==first.get("workItemId"),
          "universal approved action replay duplicated an original")
    made=care.allow(api,key,owner,OWNER_RPC,args)
    work=made.get("workItemId")
    require(work
      and (made.get("newOriginalWorkCreated") is True or
           generic and made.get("existingAction") is True)
      and (generic or made.get("responsiblePersonId")==
           "e5200000-0000-4000-8000-000000000102")
      and (generic or made.get("approvedWorkdaysIso")==[1,2,3,4,5,6,7]),
      "governor's signed mandate did not create one correct original")
    if generic:
        require(work==first.get("workItemId"),
                "the universal and domain sources generated different originals")
    repeated=care.allow(api,key,owner,OWNER_RPC,args)
    require(repeated.get("existingAction") is True
      and repeated.get("workItemId")==work,"same governor action duplicated Work")
    require(care.sql(db,"select count(*) from atlas.work_items where "
             "source_object_id in ("+literal(STATE4)+"::uuid,"
             +literal(STATE5)+"::uuid)")=="1",
            "governor approved more than one original")
    # The disclosed first original is visible in the worker's actual signed
    # native Work reader, not an invented UI/task fixture.
    today=care.allow(api,key,worker,"connected_person_my_work_self_api_v1",
                     {"p_limit":50,"p_after_allocation_id":None})
    require(any(x.get("workItemId")==work and x.get("workOn")==service
                for x in today.get("items",[])),
            "governor first visit absent from worker native My Work/Today")
    partial=care.allow(api,key,worker,care.CARE_RPC,
              care.care_args(work,PARTIAL,"weeded_partial","row_readable"))
    require(partial.get("workState")=="open" and
      care.sql(db,"select count(*) from atlas.work_items where "
        "source_object_id in ("+literal(STATE4)+"::uuid,"
        +literal(STATE5)+"::uuid)")=="1",
        "partial care advanced owner campaign without qualifying physical Done")
    done=care.allow(api,key,worker,care.CARE_RPC,
              care.care_args(work,FULL,"weeded_full","clear"))
    continuation=done.get("campaignContinuation")
    require(done.get("workState")=="completed"
      and done.get("contractVersion")=="universal_work_lifecycle_transition_v1"
      and isinstance(continuation,dict)
      and continuation.get("ok") is True
      and continuation.get("nextWorkCreated") is True,
      "accepted physical Done failed to release the next governed Work: "
      +str(continuation)[:250])
    nextwork=continuation.get("nextWorkItemId")
    nextday=continuation.get("nextServiceDate")
    require(nextwork and nextwork!=work and nextday,
        "successor did not have independent original Work and approved day")
    require(care.sql(db,
      "select count(*) from atlas.work_items where id="+literal(nextwork)+"::uuid"
      +" and work_state='open' and source_object_id="+literal(STATE5)+"::uuid"
      +" and metadata->>'sourceStandingCampaignId'="+literal(CAMPAIGN)
      +" and metadata->'sourceStandingWorkdaysIso'='[1,2,3,4,5,6,7]'::jsonb"
      +" and metadata->>'sourceAdmissionMode'='owner_standing_successor_v1'")=="1",
      "successor lost exact Bed 5, original custody, or frozen weekdays")
    require(service<nextday<=end,"successor violated governor's campaign window")
    count=care.sql(db,"select count(*) from atlas.work_items where "
        "source_object_id in ("+literal(STATE4)+"::uuid,"
        +literal(STATE5)+"::uuid)")
    require(count=="2","two Subjects did not result in exactly two originals")
    follow=care.allow(api,key,worker,"connected_person_my_work_self_api_v1",
           {"p_limit":50,"p_after_allocation_id":None})
    require(any(x.get("workItemId")==nextwork
       and x.get("workOn")==nextday and x.get("scheduleState")=="scheduled"
       for x in follow.get("items",[])),
       "successor absent from signed native Person My Work")
    outsider_work=care.allow(api,key,outsider,"connected_person_my_work_self_api_v1",
           {"p_limit":50,"p_after_allocation_id":None})
    require(all(x.get("workItemId")!=nextwork
                for x in outsider_work.get("items",[])),
          "successor leaked to unrelated Person")
    replay=care.allow(api,key,worker,care.CARE_RPC,
              care.care_args(work,FULL,"weeded_full","clear"))
    require(replay.get("idempotent") is True
        and care.sql(db,"select count(*) from atlas.work_items where "
          "source_object_id in ("+literal(STATE4)+"::uuid,"
          +literal(STATE5)+"::uuid)")=="2",
          "signed completed Result replay generated duplicate successor")
    care.deny(api,key,outsider,"connected_person_original_work_subject_self_api_v1",
           care.work_reader(nextwork,BED5),
           "Outsider cannot read newly delivered Bed 5 subject")
    print("PASS R01 signed owner -> Bed 4 original -> partial -> accepted physical Done -> "
          "single Bed 5 original with next approved day, native Today, retry and outsider denial")
    if generic:\n        print("PASS R02 universal signed governor preview, source adapter denial, " +\n              "same original Work, replay and downstream Actual/Today")\n    return ("PASS R01 genuine signed owner/worker/outsider; two independent "
            "Subject rhythm rules; one accepted Actual creates exactly one "
            "approved next original in My Work/Today; replay and denial.\n")
