#!/usr/bin/env python3
"""Genuine LOCAL GoTrue/PostgREST Program margin note authorization proof.
Fictional approved Program; separate owner/other/unbound JWT sessions. No remote
endpoints or real Program records are ever used.
"""
import argparse
import importlib.util
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parent
def load(name,filename):
    spec=importlib.util.spec_from_file_location(name,ROOT/filename)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

auth=load("local_auth","validate-atlas-c1-signed-http.py")
prog=load("program_v2","validate-atlas-universal-program-v2-signed-http.py")
READ="personal_program_author_notes_read_self_api_v1"
CREATE="personal_program_author_note_create_self_api_v1"
REVISE="personal_program_author_note_revise_self_api_v1"

def good(api,key,token,method,params):
    status,body=auth.rpc(api,key,method,params,token)
    auth.check(status==200 and isinstance(body,dict) and body.get("ok") is True,
               f"{method} returned {status} {str(body)[:180]}")
    return body

def deny(api,key,token,method,params,label):
    status,body=auth.rpc(api,key,method,params,token)
    auth.check(status in (401,403) and isinstance(body,dict),
               f"{label} unexpectedly received {status}: {str(body)[:180]}")
    if token is not None:
        auth.check(body.get("code")=="42501",
                   f"{label} must fail through source authorization, got {body}")
    print("PASS",label)

def reject(api,key,token,method,params,code,label):
    status,body=auth.rpc(api,key,method,params,token)
    auth.check(status>=400 and isinstance(body,dict) and body.get("code")==code,
               f"{label}: expected {code}; received {status} {str(body)[:180]}")
    print("PASS",label)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    a=parser.parse_args()
    auth.check(bool(re.fullmatch(
        r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
        "Refuse non-loopback Postgres")
    auth.check(auth.sql(a.db_url,
        f"select count(*) from auth.users where id in "
        f"('{prog.AUTHOR}','{prog.OTHER}','{prog.UNBOUND}')")=="3",
        "Required fictional identities are missing")
    api,key=auth.local_status()
    prog.setup_auth(a.db_url)
    author,author_claims=auth.sign_in(api,key,"program-author")
    other,other_claims=auth.sign_in(api,key,"program-other")
    unbound,unbound_claims=auth.sign_in(api,key,"program-unbound")
    for claims,user_id in ((author_claims,prog.AUTHOR),
                           (other_claims,prog.OTHER),(unbound_claims,prog.UNBOUND)):
        auth.check(claims.get("sub")==user_id and claims.get("session_id"),
                   "GoTrue token identity/session mismatch")
        auth.check(auth.sql(a.db_url,
          f"select count(*) from auth.sessions "
          f"where id='{claims['session_id']}'::uuid and user_id='{user_id}'::uuid")=="1",
                   "Token has no corresponding local signed session")
    auth.check(other_claims.get("user_metadata",{}).get("is_owner") is True,
               "Attacker-controlled owner claim fixture missing")
    print("PASS three genuine independently signed local sessions")

    source=prog.packet()
    p=good(api,key,author,prog.CREATE,{
        "p_packet":source,"p_request_key":"signed-notes-program-create"})
    program_id=p["programId"]
    note={"p_program_id":program_id,
          "p_anchor_version_id":"00000000-0000-4000-8000-000000000001",
          "p_component_key":"budget-review",
          "p_anchor_excerpt":"Compare intended category",
          "p_body":"Private functional observation for this authored source.",
          "p_request_key":"signed-notes-create"}
    deny(api,key,author,CREATE,note,"No note before canonical approved version")
    approved=good(api,key,author,prog.APPROVE,{
        "p_program_id":program_id,"p_expected_revision":1,
        "p_expected_digest":p["packetDigest"],
        "p_request_key":"signed-notes-program-approve"})
    version_id=approved["versionId"]
    first=good(api,key,author,prog.READ,{"p_program_id":program_id})
    auth.check(len(first["versions"])==1 and
               first["versions"][0]["versionId"]==version_id,
               "Missing immutable approval")
    source_version=first["versions"][0]["packet"]
    note["p_anchor_version_id"]=version_id
    deny(api,key,None,READ,{"p_program_id":program_id},"Anonymous read")
    deny(api,key,None,CREATE,note,"Anonymous create")
    deny(api,key,other,READ,{"p_program_id":program_id},"Other signed owner read")
    deny(api,key,other,CREATE,note,"Other signed owner create")
    deny(api,key,unbound,READ,{"p_program_id":program_id},"Unbound signed reader")
    deny(api,key,unbound,CREATE,note,"Unbound signed writer")
    created=good(api,key,author,CREATE,note)
    note_id=created["noteId"]
    auth.check(created["revision"]==1 and
               created["visibility"]=="author_private","Note admission not private")
    replay=good(api,key,author,CREATE,note)
    auth.check(replay["noteId"]==note_id and replay["replay"] is True,
               "Create replay not idempotent")
    reject(api,key,author,CREATE,{**note,"p_body":"Different text"},
           "23505","Conflicting create replay")
    reject(api,key,author,CREATE,
           {**note,"p_anchor_excerpt":"Not in approved source",
            "p_request_key":"signed-notes-bad-source"},
           "22023","Invented citation refused")
    deny(api,key,author,CREATE,
         {**note,"p_anchor_version_id":"00000000-0000-4000-8000-000000000002",
          "p_request_key":"signed-notes-bad-version"},
         "Wrong approved version unavailable")

    revise={"p_program_id":program_id,"p_note_id":note_id,
            "p_expected_revision":1,"p_body":"Author revised private note.",
            "p_standing":"resolved","p_request_key":"signed-notes-revise"}
    deny(api,key,None,REVISE,revise,"Anonymous revise")
    deny(api,key,other,REVISE,revise,"Other owner revise")
    revised=good(api,key,author,REVISE,revise)
    auth.check(revised["revision"]==2 and revised["standing"]=="resolved",
               "Revised note not accepted")
    auth.check(good(api,key,author,REVISE,revise)["replay"] is True,
               "Revision replay changed history")
    reject(api,key,author,REVISE,
           {**revise,"p_request_key":"signed-notes-stale",
            "p_body":"Stale note body"},
           "40001","Stale revision denied")
    saved=good(api,key,author,READ,{"p_program_id":program_id})
    auth.check(saved["readerOnly"] is True and
               saved["standing"]=="author_private" and saved["total"]==1
               and saved["truncated"] is False
               and len(saved["items"])==1,"Private note read failed")
    row=saved["items"][0]
    auth.check(row["noteId"]==note_id and row["componentKey"]=="budget-review"
               and row["anchorVersionId"]==version_id and
               row["historyTruncated"] is False and
               [x["revision"] for x in row["history"]]==[1,2],
               "Author-note history incomplete or mismatched")

    after=good(api,key,author,prog.READ,{"p_program_id":program_id})
    auth.check(len(after["versions"])==1 and
               after["versions"][0]["packet"]==source_version and
               after["draftPacket"]==source,
               "Notes changed approved or draft Program contents")
    auth.check(auth.sql(a.db_url,
       f"select count(*) from atlas.personal_program_author_note_events "
       f"where program_id='{program_id}'::uuid")=="2",
       "One note must have exactly two source revisions")

    auth.sql(a.db_url,f"""update atlas.personal_atlas_access_grants
       set state='revoked',revoked_at=now()
       where id='{prog.GRANT}'::uuid""")
    deny(api,key,author,READ,{"p_program_id":program_id},
         "Revocation denies note read with existing JWT")
    deny(api,key,author,CREATE,
         {**note,"p_request_key":"signed-notes-revoked-create"},
         "Revocation denies note create")
    deny(api,key,author,REVISE,
         {**revise,"p_expected_revision":2,
          "p_request_key":"signed-notes-revoked-revise"},
         "Revocation denies note revise")
    deny(api,key,author,prog.READ,{"p_program_id":program_id},
         "Revocation denies original Program source reader")
    auth.check(auth.sql(a.db_url,
       f"select count(*) from atlas.personal_program_author_note_events "
       f"where program_id='{program_id}'::uuid")=="2",
       "Denied requests altered append-only history")

    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text(
       "PASS signed LOCAL GoTrue/PostgREST Program margin-notes: "
       "author/other/unbound/anonymous, correct anchors, idempotent writes, "
       "stale revision denials, unchanged immutable Program and revoked JWT.\n",
       encoding="utf-8")
    print("PASS independently signed Program note owner boundaries on disposable clone")

if __name__=="__main__":
    main()
