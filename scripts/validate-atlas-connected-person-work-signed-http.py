#!/usr/bin/env python3
"""Genuine signed GoTrue/PostgREST Gate 0 Work exposure proof (local clone ONLY).

This is NOT run by source CI. Use after staging the reviewed SQL and seeding
disposable synthetic canonical People, two Ledgers, one worker's authorized
original Work and a separate withheld Work in a protected full-schema clone.
No production sessions, identities or records are used or modified.
"""
import argparse
import importlib.util
import json
import re
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("local_c1",HERE/"validate-atlas-c1-signed-http.py")
c1=importlib.util.module_from_spec(spec)
spec.loader.exec_module(c1)

FN="connected_person_authorized_ledger_work_self_api_v1"
UUID=re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",re.I)

def need(ok,message):
    c1.check(ok,message)

def request(api,key,token,ledger):
    return c1.rpc(api,key,FN,{"p_ledger_id":ledger,"p_limit":100,
                              "p_after_allocation_id":None},token)

def assert_denied(status,data,label):
    need(status in (200,401,403),f"{label}: unexpected HTTP {status}")
    if status==200:
        need(isinstance(data,dict) and data=={"ok":False,"code":"not_found"},
             f"{label}: nonuniform denial")
    print("PASS",label)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    p.add_argument("--worker-label",required=True)
    p.add_argument("--outsider-label",required=True)
    p.add_argument("--worker-ledger-id",required=True)
    p.add_argument("--other-ledger-id",required=True)
    p.add_argument("--visible-work-id",required=True)
    p.add_argument("--hidden-work-id",required=True)
    p.add_argument("--hidden-marker",default="FICTIONAL_CONFIDENTIAL_SOURCE")
    a=p.parse_args()

    need(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
         "A 127.0.0.1 disposable Postgres clone is mandatory")
    need(a.worker_label!=a.outsider_label,"Independent worker and outsider credentials required")
    for name in ("worker_ledger_id","other_ledger_id","visible_work_id","hidden_work_id"):
        need(bool(UUID.fullmatch(getattr(a,name))),f"{name} must be a UUID")
    need(a.worker_ledger_id!=a.other_ledger_id,"Two distinct Ledgers required")
    need(a.visible_work_id!=a.hidden_work_id,"Two distinct Work records required")

    api,key=c1.local_status()
    worker,worker_claims=c1.sign_in(api,key,a.worker_label)
    outsider,outsider_claims=c1.sign_in(api,key,a.outsider_label)
    need(worker!=outsider and worker_claims.get("sub")!=outsider_claims.get("sub"),
         "Independent authenticated users required")
    for label,claims in (("worker",worker_claims),("outsider",outsider_claims)):
        sid=claims.get("session_id")
        need(bool(sid and UUID.fullmatch(sid)),f"{label} missing real Auth session")
        need(c1.sql(a.db_url,
          f"select count(*) from auth.sessions where id='{sid}'::uuid and user_id='{claims['sub']}'::uuid")=="1",
          f"{label} signed session must be stored in GoTrue")

    assert_denied(*request(api,key,None,a.worker_ledger_id),"anonymous")
    assert_denied(*request(api,key,outsider,a.worker_ledger_id),"unrelated signed Person")
    assert_denied(*request(api,key,worker,a.other_ledger_id),"wrong native Ledger")

    status,data=request(api,key,worker,a.worker_ledger_id)
    need(status==200 and isinstance(data,dict) and data.get("ok") is True,
         f"Worker positive source read failed: {status}, {str(data)[:240]}")
    need(data.get("personId") is not None and data.get("ledgerId")==a.worker_ledger_id,
         "Positive response lacks exact authenticated Person or Ledger")
    items=data.get("items")
    need(isinstance(items,list),"Worker items must be an array")
    ids={x.get("workItemId") for x in items if isinstance(x,dict)}
    need(a.visible_work_id in ids,"Authorized synthetic Work missing (empty response is not a pass)")
    need(a.hidden_work_id not in ids,"Unassigned synthetic Work was exposed")
    allow={"workItemId","allocationId","ledgerId","title","workState","canReportOrdinaryCompletion"}
    for item in items:
        need(isinstance(item,dict) and set(item).issubset(allow),
             "Work projection includes unapproved source fields")
    need(a.hidden_marker not in json.dumps(data),"Private source marker disclosed")
    need(data.get("includesInstructions") is False and
         data.get("includesFarmSourceContext") is False and
         data.get("permissionAuditComplete") is False,
         "Read projection must not claim complete effective-disclosure audit")

    sid=worker_claims["session_id"]
    c1.sql(a.db_url,f"delete from auth.sessions where id='{sid}'::uuid")
    assert_denied(*request(api,key,worker,a.worker_ledger_id),
                  "revoked GoTrue session must deny even with retained JWT")

    Path(a.output).write_text(
        "PASS independent signed worker/outsider, visible/withheld exact Ledger Work,"
        " anonymous/cross-Ledger/revoked negative access; local fixture only.\n",
        encoding="utf-8")
    print("PASS synthetic local signed Work-only boundary")

if __name__=="__main__":
    main()
