#!/usr/bin/env python3
"""HELD option A U1B→U2 accepted-first signed test on a fresh LOCAL clone ONLY.

Requires exact preseeded fictional C1 people and this test's fictional mowing
source. All human policy, scope and prework decisions occur through true
independently issued GoTrue sessions and existing public source-owned RPCs.
Never use on a remote database. Not a release or comprehensive U0–U7 proof.
"""
import argparse
import datetime as dt
import importlib.util
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location(
    "uniops_native_signed",ROOT/"scripts"/"validate-atlas-work-prerequisite-signed-http.py")
if spec is None or spec.loader is None:
    raise SystemExit("Missing canonical signed identity helper")
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
c1=base.c1

ORG="e5200000-0000-4000-8000-000000000801"
LEDGER="e5200000-0000-4000-8000-000000000401"
FARM="e5200000-0000-4000-8000-000000000b01"
MOWER="e5200000-0000-4000-8000-000000000d01"
RULE="e5200000-0000-4000-8000-000000000d03"
CANDIDATE="e5200000-0000-4000-8000-000000000d05"
OWNER_PERSON="e5200000-0000-4000-8000-000000000101"
WORKER_PERSON="e5200000-0000-4000-8000-000000000102"
POLICY={"eligibilityMode":"standing_stewardship",
        "desiredOutcome":"A true observation and appropriately completed fictional mowing cycle",
        "standingPurpose":"Observe and care for the known fictional mowing area only",
        "seasonKeys":[]}

def check(ok, why):
    if not ok: raise AssertionError(why)

def sql(db,query):
    return c1.sql(db,query)

def rpc(api,key,token,name,params):
    return c1.rpc(api,key,name,params,token)

def allow(api,key,token,name,params,label):
    status,obj=rpc(api,key,token,name,params)
    ok=status==200 and isinstance(obj,dict) and obj.get("ok") is True
    diagnostic=(
      "INBOX" if label=="worker reads source-owned preoriginal inbox"
      else "ACCEPT" if label=="worker independently accepts known preoriginal offer"
      else None)
    if diagnostic and not ok:
        # Report only enum/allowlisted error class from LOCAL synthetic actor.
        # Never print the private PostgREST response, message, token or Person.
        codes={"42501":"source_permission","23514":"source_constraint",
               "23505":"source_conflict","22023":"source_argument",
               "42883":"missing_function","42P01":"missing_relation"}
        code=obj.get("code") if isinstance(obj,dict) else None
        http={400:"bad_request",401:"unauthorized",403:"forbidden",
              404:"not_found",409:"conflict"}.get(status,
              "server_failure" if isinstance(status,int) and status>=500
              else "other_status")
        print("U2_WORKER_"+diagnostic+"_HTTP_CLASS="+http,flush=True)
        print("U2_WORKER_"+diagnostic+"_ERROR_CLASS="+codes.get(code,"other_or_unspecified"),flush=True)
    check(ok,
          f"{label} failed as signed RPC (status={status}, code={obj.get('code') if isinstance(obj,dict) else 'unknown'})")
    print("PASS",label,flush=True)
    return obj

def deny(api,key,token,name,params,label,codes=("42501",)):
    status,obj=rpc(api,key,token,name,params)
    check(status in (400,401,403,409) and isinstance(obj,dict)
          and (obj.get("code") in codes or (token is None and status in (401,403))),
          f"{label}: expected authorized source denial, status={status}, code={obj.get('code') if isinstance(obj,dict) else 'unknown'}")
    print("PASS",label)

def rule_params(kind,ref,action,policy=POLICY):
    return {"p_organization_id":ORG,"p_ledger_id":LEDGER,"p_farm_id":FARM,
            "p_source_rule_id":RULE,"p_scope_kind":kind,"p_scope_ref":ref,
            "p_policy":policy,"p_decision":"active",
            "p_expected_previous_version_id":None,"p_action_id":action}

def offer_params(scope,action):
    day=dt.datetime.now(dt.timezone.utc).date()+dt.timedelta(days=1)
    return {"p_organization_id":ORG,"p_ledger_id":LEDGER,"p_farm_id":FARM,
            "p_source_rule_id":RULE,"p_accepted_standing_scope_id":scope,
            "p_first_service_day":day.isoformat(),
            "p_campaign_end_date":(day+dt.timedelta(days=6)).isoformat(),
            "p_approved_iso_weekdays":[day.isoweekday()],"p_timezone_name":"UTC",
            "p_reason":"Fictional mowing cycle with original worker acceptance before any Work.",
            "p_action_id":action}

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    check(bool(re.fullmatch(
        r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres",
        a.db_url)), "Only exact disposable localhost Postgres accepted")
    check(sql(a.db_url,"select current_database()")=="postgres", "Wrong database")
    check(sql(a.db_url,
        f"select count(*) from atlas.rhythm_state s join atlas.mowing_area_state m "
        f"on m.object_id=s.subject_id where s.id='{CANDIDATE}'::uuid "
        f"and s.rhythm_rule_id='{RULE}'::uuid and s.rhythm_key='mowing'")=="1",
        "Synthetic known mowing source is absent")
    check(sql(a.db_url,"select count(*) from atlas.governed_prework_candidate_offers_v1")=="0",
          "There must be no policy-derived offers before a signed person acts")
    check(sql(a.db_url,"select count(*) from atlas.company_work_standing_assignment_scopes")=="0",
          "There must be no preaccepted standing scopes")
    count_before=int(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid"))
    api,key=c1.local_status()
    identities=base.setup_auth(a.db_url)
    signed={}
    for name,uid in identities:
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("session_id"),
              "Actual independent GoTrue session required: "+name)
        check(sql(a.db_url,("select count(*) from auth.sessions where id='"+
                  claims["session_id"]+"'::uuid and user_id='"+uid+"'::uuid"))=="1",
              "Actual signed session not stored for "+name)
        signed[name]=(token,claims)
    check(len({v[0] for v in signed.values()})==4,"Independent tokens not established")
    owner,worker,outsider=(signed[k][0] for k in ("owner","worker","outsider"))
    print("PASS true separate signed owner, worker, outsider and no-seat local sessions")

    proposal={"p_organization_id":ORG,"p_ledger_id":LEDGER,
        "p_worker_person_id":WORKER_PERSON,"p_organization_unit_id":None,
        "p_coverage_mode":"ledger_all_work","p_operation_class":None,
        "p_terms":"Fictional ongoing responsibility for a disclosed mowing area of this exact Ledger only.",
        "p_valid_until":None}
    propose="propose_native_ledger_standing_scope_owner_self_api_v1"
    respond_scope="respond_native_ledger_standing_scope_self_api_v1"
    deny(api,key,worker,propose,proposal,"worker cannot propose their own authority")
    deny(api,key,outsider,propose,proposal,"outsider cannot offer native standing scope")
    scope=allow(api,key,owner,propose,proposal,
         "governor genuinely proposes native scope")["scopeId"]
    check(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")==str(count_before),
          "Scope proposal pre-created Work")
    deny(api,key,outsider,respond_scope,{"p_scope_id":scope,"p_decision":"accept"},
         "outsider cannot accept worker's scope")
    allow(api,key,worker,respond_scope,
          {"p_scope_id":scope,"p_decision":"accept"},
          "worker genuinely accepts native Ledger standing scope")

    # Identity and physical-condition disclosure is separately authorized,
    # never inferred from membership, scope acceptance or the Rulebook.
    for person in (OWNER_PERSON,WORKER_PERSON):
        for klass in ("identity","condition"):
            allow(api,key,owner,"governor_set_subject_disclosure_self_api_v1",{
              "p_organization_id":ORG,"p_ledger_id":LEDGER,
              "p_target_person_id":person,"p_subject_domain":"spatial",
              "p_subject_kind":"growing_object","p_subject_id":MOWER,
              "p_disclosure_class":klass,"p_decision_kind":"grant",
              "p_source_action_id":str(__import__("uuid").uuid5(
                  __import__("uuid").NAMESPACE_DNS, "uniops-test-"+person+klass)),
              "p_reason":"Fictional mowing scope requires separate current Subject disclosure."
            },"governor grants one exact "+klass+" disclosure")

    offer_name="offer_next_governed_prework_candidate_self_api_v1"
    rule_name="adopt_governed_farm_rulebook_scope_self_api_v1"
    first_params=offer_params(scope,"e5200000-0000-4000-8000-000000000e01")
    deny(api,key,worker,offer_name,first_params,
         "worker cannot issue own preoriginal offer")
    deny(api,key,outsider,offer_name,first_params,
         "outsider cannot issue preoriginal offer")
    # Before a property umbrella, the source may decline without inventing
    # a candidate; no signed rule adoption has been performed.
    premature=allow(api,key,owner,offer_name,first_params,
                    "root's prepolicy candidate search is bounded")
    check(premature.get("offerCreated") is False,
          "No policy yet: should not have created Work or offer")
    check(sql(a.db_url,"select count(*) from atlas.governed_prework_candidate_offers_v1")=="0",
          "No policy yet: candidate mutated")

    property_args=rule_params("property","property",
                   "e5200000-0000-4000-8000-000000000e02")
    deny(api,key,worker,rule_name,property_args,
         "worker cannot adopt current governance policy")
    p1=allow(api,key,owner,rule_name,property_args,
             "native governor adopts exact property Rulebook")
    check(p1.get("policyExecutable") is False and p1.get("workCreated") is False,
          "Rulebook policy adoption must not itself issue Work")
    subject_args=rule_params("subject",MOWER,
                   "e5200000-0000-4000-8000-000000000e03")
    p2=allow(api,key,owner,rule_name,subject_args,
             "governor independently approves exact mowing Subject")
    check(p2.get("policyExecutable") is False,
          "Subject policy is not standalone executor")
    check(sql(a.db_url,"select count(*) from atlas.governed_farm_rulebook_scope_versions_v1")=="2",
          "Expected exactly property+subject immutable versions")

    created=allow(api,key,owner,offer_name,first_params,
                  "native root offers one source-selected mowing candidate")
    # Bound diagnostic data to a small fixed enum, without printing the
    # offer UUID, source Subject, private server response or SQL content.
    # Distinguishes a legitimate empty-source hold from a mismatched receipt.
    # The pinned U2 success receipt has state, offerId, candidateId,
    # and negative Work/physical flags. It intentionally does NOT return
    # offerCreated:true; that key is exclusive to the no-candidate result.
    # See original pinned U2A source lines 452-461, not a later UI adapter.
    valid_offer=(created.get("contractVersion")=="governed_prework_candidate_offer_v1"
       and created.get("state")=="offered"
       and created.get("candidateId")==CANDIDATE
       and isinstance(created.get("offerId"),str)
       and bool(re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}",
                             created.get("offerId","")))
       and created.get("replayed") is False
       and created.get("originalWorkCreated") is False
       and created.get("responsibilityCreated") is False
       and created.get("physicalConditionAsserted") is False)
    if valid_offer:
        selection="exact_source_offered"
    elif (created.get("offerCreated") is False and
          created.get("state")=="no_source_eligible_candidate"):
        selection="no_eligible_source"
    elif created.get("state")=="offered":
        selection="unexpected_offered_source"
    else:
        selection="unrecognized_receipt"
    print("U2_SOURCE_SELECTION="+selection,flush=True)
    check(valid_offer, "Only exact pinned U2 source-selected offer receipt is admissible")
    offer=created["offerId"]
    check(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")==str(count_before),
          "Offer itself fabricated an original Work")

    response="respond_governed_prework_candidate_self_api_v1"
    final="finalize_accepted_governed_prework_self_api_v1"
    args_accept={"p_offer_id":offer,"p_decision":"accept",
                 "p_action_id":"e5200000-0000-4000-8000-000000000e04"}
    deny(api,key,outsider,response,args_accept,
         "outsider cannot accept recipient-specific offer")
    deny(api,key,owner,response,args_accept,
         "root cannot impersonate recipient acceptance")
    deny(api,key,owner,final,{"p_offer_id":offer},
         "governor may not finalize Work before worker consent")
    # Non-authoritative local read-only candidate observation. This does
    # NOT replace the subsequent independently signed worker RPC; it only
    # distinguishes source eligibility from worker-authn/authz failure.
    candidate_state=sql(a.db_url,
       "select case when atlas.governed_prework_offer_still_admissible_v1('"
       +offer+"'::uuid) then 'eligible' else 'ineligible' end")
    state=candidate_state if candidate_state in ("eligible","ineligible") else "unclassified"
    print("U2_WORKER_ACCEPT_SOURCE_PREFLIGHT="+state,flush=True)
    # Read-only LOCAL fixture custody: compare only known synthetic worker
    # identity, one active principal, recipient and original offer. Do not
    # authorize from this check; the signed inbox/response are still mandatory.
    identity=sql(a.db_url,f"""
       select case when
         (select count(*) from reality.auth_person_bindings b
          where b.auth_user_id='{c1.WORKER}'::uuid
            and b.person_entity_id='{WORKER_PERSON}'::uuid
            and b.binding_state='active' and b.retired_at is null)=1
         and (select count(*) from atlas.principals p
              where p.user_id='{c1.WORKER}'::uuid
                and p.person_id='{WORKER_PERSON}'::uuid
                and p.status='active')=1
         and (select count(*) from atlas.principals p
              where p.person_id='{WORKER_PERSON}'::uuid
                and p.status='active')=1
         and (select count(*) from atlas.governed_prework_candidate_offers_v1 o
              where o.id='{offer}'::uuid
                and o.target_person_id='{WORKER_PERSON}'::uuid)=1
        then 'aligned' else 'misaligned' end""")
    identity_class=identity if identity in ('aligned','misaligned') else 'unclassified'
    print("U2_WORKER_IDENTITY_FIXTURE="+identity_class,flush=True)
    # This exact existing U2A signed inbox verifies worker can actually
    # observe THEIR one known original offer, not a queried roster.
    inbox=allow(api,key,worker,"read_governed_prework_candidate_inbox_self_api_v1",{},
                "worker reads source-owned preoriginal inbox")
    items=inbox.get("items")
    good_inbox=(inbox.get("contractVersion")=="governed_prework_candidate_inbox_v1"
       and isinstance(items,list) and len(items)==1
       and items[0].get("offerId")==offer
       and items[0].get("sourceCandidateIdentityDisclosed") is True
       and items[0].get("originalWorkCreated") is False)
    inbox_class=('one_matching' if good_inbox else
                 'empty' if isinstance(items,list) and not items else
                 'other_or_unrecognized')
    print("U2_WORKER_INBOX_RESULT="+inbox_class,flush=True)
    check(good_inbox,"Worker must privately read one exact authorized offer")
    accepted=allow(api,key,worker,response,args_accept,
                   "worker independently accepts known preoriginal offer")
    check(accepted.get("acceptanceIsNotAssignment") is True
          and accepted.get("originalWorkCreated") is False,
          "Recipient consent is not assignment")
    check(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")==str(count_before),
          "Acceptance itself created Work")
    replay=allow(api,key,worker,response,args_accept,
                 "identical worker acceptance is idempotent")
    check(replay.get("replayed") is True,"Recipient replay wrote a second decision")
    deny(api,key,worker,response,dict(args_accept,p_action_id=
         "e5200000-0000-4000-8000-000000000e05"),
         "changed response cannot reuse already resolved offer",("23514",))
    deny(api,key,worker,final,{"p_offer_id":offer},
         "worker cannot finalize Work as governing root")
    deny(api,key,outsider,final,{"p_offer_id":offer},
         "outsider cannot finalize accepted Work")
    finish=allow(api,key,owner,final,{"p_offer_id":offer},
                 "governor creates exact one original after worker accepts")
    new_work=finish.get("workItemId")
    check(new_work and finish.get("originalWorkCreatedNow") is True
          and finish.get("workerAcceptedFirst") is True
          and finish.get("principalClockAdmitted") is False
          and finish.get("nextOriginalNotPrecreated") is True,
          "Source writer did not preserve canonical original / no Clock")
    check(sql(a.db_url,f"""
       select count(*) from atlas.work_items w
       join atlas.company_work_native_ledger_relevance rel on rel.work_item_id=w.id
       join atlas.work_allocations a on a.work_item_id=w.id
       join atlas.work_execution_plans p on p.work_item_id=w.id
       where w.id='{new_work}'::uuid and w.organization_id='{ORG}'::uuid
         and w.source_object_type='rhythm_state' and w.source_object_id='{CANDIDATE}'::uuid
         and w.work_state='open' and rel.ledger_id='{LEDGER}'::uuid
         and rel.attribution_state='active' and a.state='active'
         and a.assignee_canonical_person_id='{WORKER_PERSON}'::uuid
         and p.plan_state='active' and p.responsible_allocation_id=a.id
       """)=="1","One canonical original/recipient/plan/native Ledger source not consistent")
    check(sql(a.db_url,f"select count(*) from atlas.work_items where organization_id='{ORG}'::uuid")==str(count_before+1),
          "Original Work count must increase by exactly one")
    again=allow(api,key,owner,final,{"p_offer_id":offer},
                "same offered action reuses the identical original Work")
    check(again.get("workItemId")==new_work and again.get("replayed") is True
          and again.get("originalWorkCreatedNow") is False,
          "Finalization replay duplicated original")
    check(sql(a.db_url,f"select count(*) from atlas.work_execution_results where work_item_id='{new_work}'::uuid")=="0",
          "No physical Result can be synthesized by consent")
    check(sql(a.db_url,f"select count(*) from atlas.work_result_acceptances where work_item_id='{new_work}'::uuid")=="0",
          "No Result acceptance may be invented by issuing Work")
    # A signed actor's existing JWT is not authority after session removal.
    owner_session=signed["owner"][1]["session_id"]
    sql(a.db_url,"delete from auth.sessions where id='"+owner_session+"'::uuid")
    deny(api,key,owner,final,{"p_offer_id":offer},
         "revoked root session cannot replay governed original")
    out=Path(a.output)
    out.write_text(
      "PASS genuine separate signed local root/worker/outsider/no-seat; native "
      "scope proposed and accepted; exact mowing Subject disclosures; property "
      "and Subject rule versions approved by current root; no offer without "
      "policy; worker consent before canonical original; outsider, worker, root "
      "impersonation and revoked session denied; exactly one original, active "
      "allocation and date plan, replay, no physical Result, no accepted Actual, "
      "no Clock or automatic next original. NOT TESTED: U1A overlap, historical "
      "cancel on new original, post-Result 6A eligibility or production.\n",
      encoding="utf-8")
    print("PASS UNI-OPS option A U1B/U2 genuinely signed first original Work, no successor")

if __name__=="__main__":main()
