#!/usr/bin/env python3
"""Signed LOCAL GoTrue/PostgREST proof for Person source-history read membrane."""
import argparse, importlib.util, re
from datetime import datetime, timezone
from pathlib import Path
here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("weight_source",here/"validate-atlas-person-weight-signed-http.py")
weight=importlib.util.module_from_spec(spec)
spec.loader.exec_module(weight)
auth=weight.auth
ONE,TWO=weight.ONE,weight.TWO
TASK="a1400000-0000-4000-8000-000000000601"
OTHER_TASK="a1400000-0000-4000-8000-000000000602"
def must(ok,msg):
    auth.check(ok,msg)
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a=p.parse_args()
    must(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
         "Refusing a non-local or remote database")
    must(auth.sql(a.db_url,f"select count(*) from auth.users where id in ('{ONE}','{TWO}')")=="2",
         "Two fictional People must be present")
    api,key=auth.local_status()
    weight.setup_auth(a.db_url)
    first,c1=auth.sign_in(api,key,"weight-one")
    second,c2=auth.sign_in(api,key,"weight-two")
    for claims,owner in ((c1,ONE),(c2,TWO)):
        must(claims.get("sub")==owner and bool(claims.get("session_id")),"Real local JWT required")
        session=claims["session_id"]
        must(auth.sql(a.db_url,f"select count(*) from auth.sessions where id='{session}'::uuid and user_id='{owner}'::uuid")=="1",
             "Real saved Auth session required")
    must(c2.get("user_metadata",{}).get("is_owner") is True,"Foreign Person metadata claim fixture missing")
    day=datetime.now(timezone.utc).date().isoformat()
    body={"p_start_date":day,"p_end_date":day,"p_timezone":"UTC","p_limit":100}
    def request(jwt,payload):
        return auth.rpc(api,key,"person_period_source_history_self_api_v1",payload,jwt)
    code,err=request(None,body)
    must(code in (401,403),"Anonymous Person source read should be denied")
    code,first_page=request(first,body)
    must(code==200 and first_page.get("ok") is True and
         first_page.get("contractVersion")=="person_period_source_history_v1",
         f"Authenticated first Person history error: HTTP {code}, {str(first_page)[:400]}")
    owned={row["source"]["id"] for row in first_page["items"]}
    expected={weight.FIRST,weight.BEFORE,TASK}
    must(owned==expected,f"First Person ownership/coverage mismatch: {owned}")
    must(first_page["hasMore"] is False,"Complete period should not be truncated")
    for item in first_page["items"]:
        if item["source"]["id"]==TASK:
            must(item["entryKind"]=="personal_task_marked_complete" and
                 item["evidenceStanding"]=="task_status_only" and item.get("occurredAt") is None,
                 "Task completion was promoted to physical outcome")
        else:
            must(item["entryKind"]=="first_party_observation" and
                 item["timeStanding"]=="page_context_only",
                 "Page date was promoted to observation time")
    code,foreign=request(second,body)
    must(code==200 and foreign.get("ok") is True,"Foreign Person own history unavailable")
    other_ids={row["source"]["id"] for row in foreign["items"]}
    must(other_ids=={weight.FOREIGN,OTHER_TASK},f"Cross-Person leak or coverage gap: {other_ids}")
    seen=[]
    cursor=None
    for _ in range(6):
        payload={**body,"p_limit":1}
        if cursor:
            payload.update(p_after_day=cursor["day"],
                           p_after_recorded_at=cursor["recordedAt"],
                           p_after_kind=cursor["kind"],
                           p_after_source_id=cursor["sourceId"])
        code,page=request(first,payload)
        must(code==200 and page.get("ok") is True and len(page["items"])==1,
             f"Signed cursor failed: {code} {str(page)[:400]}")
        ident=page["items"][0]["source"]["id"]
        must(ident not in seen,"Cursor repeated an original source")
        seen.append(ident)
        if not page["hasMore"]:
            must(page.get("nextCursor") is None,"Final cursor must be empty")
            break
        cursor=page["nextCursor"]
        must(bool(cursor),"Nonfinal page missing cursor")
    must(set(seen)==expected and len(seen)==len(expected),"Cursor skipped/duplicated source")
    for invalid in ({**body,"p_limit":201},{**body,"p_after_day":day}):
        code,err=request(first,invalid)
        must(code>=400 and isinstance(err,dict) and err.get("code")=="22023",
             "Invalid period or incomplete cursor must fail source validation")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text("PASS genuine local GoTrue Person period reader, source custody, cursor and isolation\n")
    print("PASS real signed local Person period history and source truth")
if __name__=="__main__":main()
