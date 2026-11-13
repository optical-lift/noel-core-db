#!/usr/bin/env python3
"""PRE1 retired RPC endpoint + retained v2 signed positive, DISPOSABLE LOCAL ONLY.

Invoked after the trusted ACCESS03A/03B signed local probe on an exact-SHA
PRE1 candidate clone. Never contacts Production, creates live users or releases SQL.
"""
import argparse
import importlib.util
import re
import subprocess
import time
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location(
    "access03c_pre1_existing_signed",HERE/"validate-atlas-access03-zone-retirement-signed-http.py")
existing=importlib.util.module_from_spec(spec)
spec.loader.exec_module(existing)
c1=existing.c1
FARM=existing.FARM
CYCLE=existing.CYCLE
ORG="e5200000-0000-4000-8000-000000000801"
TASK="e5200000-0000-4000-8000-000000000d31"
OWNER_MEMBERSHIP="e5200000-0000-4000-8000-000000000d32"
TASK_LINK="e5200000-0000-4000-8000-000000000d33"
OBJECT="e5200000-0000-4000-8000-000000000b03"
KEY="clone-upick-bed-3"
TITLE="Clone PRE1 retained Tending v2 context"
V1="/rest/v1/rpc/tending_task_context_v1"
V2="/rest/v1/rpc/tending_task_context_v2"

def check(ok,message):
    if not ok:
        raise AssertionError("ACCESS03C-PRE1 "+message)

def require_missing_rpc(status,payload,label):
    """404/PGRST202 only; 404/PGRST205 means whole schema inaccessible."""
    code=payload.get("code") if isinstance(payload,dict) else None
    check(status==404 and code=="PGRST202",
          label+" must be resolved-schema missing FUNCTION (404/PGRST202), "
          "not denial or whole-schema omission; HTTP="+str(status)+" code="+str(code))

def snapshot(db):
    return tuple(c1.sql(db,"select count(*) from atlas."+table)
                 for table in ("tasks","work_items","growing_objects",
                               "crop_cycles","care_state_history","zones",
                               "farm_memberships","task_objects","object_state",
                               "operation_classes"))

def local_sql(db,query):
    try:
        return c1.sql(db,query)
    except subprocess.CalledProcessError as exc:
        # This runner uses only fictional source records and LOCALHOST.
        # Log the PostgreSQL error without printing SQL, keys or row bodies.
        errors=[line.strip() for line in (exc.stderr or "").splitlines()
                if line.lstrip().startswith("ERROR:")]
        detail=errors[0] if errors else "no SQL ERROR line supplied"
        raise AssertionError("ACCESS03C-PRE1 local synthetic SQL rejected: "
                             +detail[:500]) from None

def verify_rest(api,key,tokens,db):
    # The earlier signed ACCESS03B pass proves the atlas REST schema exists.
    # Independently prove v2 resolves at the actual signed REST endpoint.
    # The v2 implementation requires BOTH native root AND a legacy farm seat.
    check(local_sql(db,f"""select count(*) from atlas.farm_memberships
      where user_id='{c1.OWNER}'::uuid and farm_id='{FARM}'::uuid""")=="0",
          "owner legacy membership already present; synthetic state drift")
    for table,identifier in (("tasks",TASK),("farm_memberships",OWNER_MEMBERSHIP),
                             ("task_objects",TASK_LINK)):
        check(local_sql(db,f"select count(*) from atlas.{table} where id='{identifier}'::uuid")=="0",
              "synthetic test ID collision: "+table)

    # The task-object link synchronizes a *derived* object_state record,
    # even for a skipped/nonactive task. Reject any pre-existing state for
    # this exact fictional object before permitting cleanup at test close.
    check(local_sql(db,f"""select count(*) from atlas.object_state
        where object_id='{OBJECT}'::uuid""")=="0",
          "pre-existing fictional object_state; refuse test-only cleanup")
    baseline=snapshot(db)

    # Production's source-owned operation catalog is TABLE DATA, not DDL,
    # and is absent from the schema-only clone. Pin exactly the reviewed
    # canonical "water_nourish" catalog entry; never disable the foreign key
    # or replace the real operation classifier with an invented code.
    class_baseline=local_sql(db, """select count(*)
        from atlas.operation_classes where stable_key='water_nourish'""")
    check(class_baseline in ("0","1"),"local operation catalog identity drift")
    if class_baseline=="0":
        local_sql(db, """insert into atlas.operation_classes(
            stable_key,label,operation_domain,definition,active,metadata)
            values('water_nourish','Water / nourish','care',
              'Supply water or comparable direct nourishment to sustain present growth.',
              true,'{}'::jsonb)""")
    check(local_sql(db, """select count(*) from atlas.operation_classes
        where stable_key='water_nourish'
          and label='Water / nourish' and operation_domain='care'
          and definition='Supply water or comparable direct nourishment to sustain present growth.'
          and active and metadata='{}'::jsonb""")=="1",
          "local operation class is not the exact reviewed production source")

    local_sql(db,f"""insert into atlas.farm_memberships(
        id,user_id,farm_id,role,worker_key,active,permissions)
        values('{OWNER_MEMBERSHIP}'::uuid,'{c1.OWNER}'::uuid,'{FARM}'::uuid,
        'owner','pre1-synthetic-owner',true,'{{"cloneFixture":true}}'::jsonb)""")
    # v2 reads ANY non-archived Tending task. This is a historical RPC
    # compatibility test, not a new active Work release. A synthetic open
    # task needs real policy/occurrence evidence from the Work engine.
    local_sql(db,f"""insert into atlas.tasks(
        id,farm_id,organization_id,title,task_type,status,
        action_key,visibility_scope,metadata)
        values('{TASK}'::uuid,'{FARM}'::uuid,'{ORG}'::uuid,'{TITLE}',
        'general','skipped','water','farm_shared',
        '{{"cloneFixture":true,"pre1HistoricalRouteTest":true}}'::jsonb)""")
    check(local_sql(db,f"""select count(*) from atlas.tasks
      where id='{TASK}'::uuid and farm_id='{FARM}'::uuid
        and status='skipped' and visibility_scope='farm_shared'""")=="1",
          "non-active synthetic task changed unexpectedly by Work engine")
    local_sql(db,f"""insert into atlas.task_objects(id,task_id,object_id)
        values('{TASK_LINK}'::uuid,'{TASK}'::uuid,'{OBJECT}'::uuid)""")
    check(local_sql(db,f"""select count(*) from atlas.tending_task_track_v1
      where farm_id='{FARM}'::uuid and task_id='{TASK}'::uuid
        and object_key='{KEY}' and crop_cycle_id='{CYCLE}'::uuid""")=="1",
          "synthetic task+object+crop reader has no actual source")

    # Existing local signed actors are reused: no owner/root privilege forged.
    body={"p_farm_id":FARM,"p_task_id":TASK,"p_object_key":KEY}
    status,packet=existing.request(api,key,tokens["owner"],V2,"POST",body)
    bed=packet.get("bed") if isinstance(packet,dict) else None
    check(status==200 and isinstance(bed,dict)
          and bed.get("taskTitle")==TITLE and bed.get("bedKey")==KEY
          and bed.get("releasedTaskId")==TASK and bed.get("cropCycleId")==CYCLE
          and bed.get("isActionableNow") is False,
          "signed native governor + existing legacy seat lost non-active v2 source "
          "positive; HTTP="+str(status))
    print("PASS ACCESS03C-PRE1 signed retained v2 owner non-active task/object/crop positive")

    for actor in ("worker","outsider","no-seat"):
        code,blocked=existing.request(api,key,tokens[actor],V2,"POST",body)
        existing.private_missing(code,blocked,"PRE1 retained v2 withheld "+actor,True)
    code,blocked=existing.request(api,key,None,V2,"POST",body)
    existing.private_missing(code,blocked,"PRE1 retained v2 anonymous denied",False)

    check(local_sql(db,"select to_regprocedure('atlas.tending_task_context_v1(uuid,uuid,text)') is null")=="t"
          and local_sql(db,"select to_regprocedure('atlas.tending_card_json_v1(uuid,jsonb,boolean)') is null")=="t",
          "exact two v1 catalog identities still present")
    check(local_sql(db,"select to_regprocedure('atlas.tending_task_context_v2(uuid,uuid,text,text)') is not null")=="t",
          "v2 catalog identity missing")
    local_sql(db,"NOTIFY pgrst, 'reload schema'")
    old_body={"p_farm_id":FARM,"p_task_id":TASK}
    # PGRST202 is the absence of the function in the loaded atlas schema,
    # NOT PGRST205 (missing schema), HTTP 403 (authorization), or 42883
    # (stale cache invoking a now-missing PostgreSQL function).
    for attempt in range(90):
        status,packet=existing.request(api,key,tokens["owner"],V1,"POST",old_body)
        error=packet.get("code") if isinstance(packet,dict) else None
        if status==404 and error=="PGRST202":
            require_missing_rpc(status,packet,"retired v1 owner call")
            break
        if status==404 and error in ("PGRST205","42883") and attempt<89:
            time.sleep(0.5)
            continue
        require_missing_rpc(status,packet,"retired v1 owner call")
    else:
        raise AssertionError("ACCESS03C-PRE1 schema cache did not retire v1 within 45s")

    for actor in ("worker","outsider","no-seat"):
        status,packet=existing.request(api,key,tokens[actor],V1,"POST",old_body)
        require_missing_rpc(status,packet,"retired v1 "+actor+" call")
    status,packet=existing.request(api,key,None,V1,"POST",old_body)
    require_missing_rpc(status,packet,"retired v1 anonymous call")
    print("PASS ACCESS03C-PRE1 signed retired context v1 404/PGRST202 (not PGRST205/42501)")

    # v2 must remain valid after the same schema-cache reload as v1 removal.
    status,packet=existing.request(api,key,tokens["owner"],V2,"POST",body)
    check(status==200 and isinstance(packet,dict)
          and isinstance(packet.get("bed"),dict)
          and packet["bed"].get("releasedTaskId")==TASK,
          "v2 positive lost after v1 PostgREST cache reload")
    print("PASS ACCESS03C-PRE1 signed retained v2 positive after PostgREST reload")

    # Only dispose of our extra fictional test records, not original fixture.
    local_sql(db,f"delete from atlas.task_objects where id='{TASK_LINK}'::uuid")
    local_sql(db,f"delete from atlas.tasks where id='{TASK}'::uuid")
    local_sql(db,f"delete from atlas.farm_memberships where id='{OWNER_MEMBERSHIP}'::uuid")
    # The genuine task-link insert/delete trigger calls
    # refresh_object_active_task_count_v1. Its count sync leaves a derived
    # object_state row with task_count_synced_at after the link disappears.
    # The baseline above proved this exact fictional object had NO such row.
    # Delete only the count-only row created by this test. Fail closed on
    # unexpected metadata or real care/operational state.
    derived_state_guard=f"""object_id='{OBJECT}'::uuid
        and farm_id='{FARM}'::uuid and active_task_count=0
        and metadata ? 'task_count_synced_at'
        and metadata=jsonb_build_object(
            'task_count_synced_at',metadata->'task_count_synced_at')
        and life_status='open' and care_state='unknown'
        and operational_truth is null and last_touched_at is null"""
    check(local_sql(db,"select count(*) from atlas.object_state where "+
                    derived_state_guard)=="1",
          "synthetic count-only object_state source drift; refuse cleanup")
    # Query the affected-row COUNT as a SELECT. Direct DELETE ... RETURNING
    # also emits a psql command tag, which is not a bare '1' and caused
    # protected run #43344788552 to fail AFTER the exact row-shape guard.
    # This changes only TEST OUTPUT verification; the guarded DELETE is
    # identical and still runs solely on disposable localhost.
    cleanup_sql=("with deleted as (delete from atlas.object_state where "+
                 derived_state_guard+" returning object_id) "+
                 "select count(*) from deleted")
    check(local_sql(db,cleanup_sql)=="1",
          "synthetic object_state cleanup affected unexpected row count")
    check(local_sql(db,f"""select count(*) from atlas.object_state
          where object_id='{OBJECT}'::uuid""")=="0",
          "synthetic object_state survived scoped cleanup")
    if class_baseline=="0":
        local_sql(db, """delete from atlas.operation_classes
            where stable_key='water_nourish'
              and label='Water / nourish'
              and operation_domain='care'
              and metadata='{}'::jsonb""")
    check(snapshot(db)==baseline,
          "original synthetic Work/crop/care/zone and extra test-table counts changed")
    for table,identifier in (("tasks",TASK),("farm_memberships",OWNER_MEMBERSHIP),
                             ("task_objects",TASK_LINK)):
        check(local_sql(db,f"select count(*) from atlas.{table} where id='{identifier}'::uuid")=="0",
              "synthetic local cleanup incomplete: "+table)
    print("PASS ACCESS03C-PRE1 signed scoped synthetic source-count and cleanup preservation")

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",
                            args.db_url)), "refuses nonlocal database")
    api,key=c1.local_status()
    tokens={}
    for name,uid in (("owner",c1.OWNER),("worker",c1.WORKER),
                     ("outsider",c1.OUTSIDER),("no-seat",c1.NO_SEAT)):
        token,claims=c1.sign_in(api,key,name)
        check(claims.get("sub")==uid and claims.get("role")=="authenticated"
              and bool(claims.get("session_id")),name+" missing signed subject")
        check(local_sql(args.db_url,f"""select count(*) from auth.sessions
            where id='{claims["session_id"]}'::uuid and user_id='{uid}'::uuid""")=="1",
              name+" signed session not persisted")
        tokens[name]=token
    check(len(tokens)==4,"four independent local signed subjects absent")
    verify_rest(api,key,tokens,args.db_url)
    Path(args.output).write_text(
        "PASS ACCESS03C-PRE1 signed v1 404/PGRST202 and retained v2 owner-positive; "
        "non-governors denied; scoped synthetic source cleanup/no net row-count change\n")

if __name__=="__main__":
    main()
