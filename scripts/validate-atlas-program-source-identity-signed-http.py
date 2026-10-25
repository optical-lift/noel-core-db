#!/usr/bin/env python3
"""Local signed auth source identity test on a disposable production-schema clone only."""
import argparse
import importlib.util
import re
from pathlib import Path

P = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("v2",P / "validate-atlas-universal-program-v2-signed-http.py")
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
auth = v2.auth
LOOKUP = "personal_program_author_same_sources_self_api_v1"
FORK = "personal_program_author_create_distinct_self_api_v1"

def get_matches(api,key,token,sources):
    return v2.accepted(api,key,token,LOOKUP,{"p_sources":sources})["items"]

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    a = p.parse_args()
    v2.expect(bool(re.fullmatch(r"postgres(ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url)),
              "Only disposable local PostgreSQL is allowed")
    v2.expect(auth.sql(a.db_url,
      f"select count(*) from auth.users where id in ('{v2.AUTHOR}','{v2.OTHER}','{v2.UNBOUND}')")=="3",
      "Missing 3 fictional GoTrue users")
    api,key = auth.local_status()
    v2.setup_auth(a.db_url)
    author,ac=auth.sign_in(api,key,"program-author")
    other,bc=auth.sign_in(api,key,"program-other")
    unbound,uc=auth.sign_in(api,key,"program-unbound")
    for token_claim,uid in ((ac,v2.AUTHOR),(bc,v2.OTHER),(uc,v2.UNBOUND)):
        v2.expect(token_claim.get("sub")==uid and token_claim.get("session_id"),
            "Signed identity must be specific to issued local GoTrue session")
        v2.expect(auth.sql(a.db_url,
            f"select count(*) from auth.sessions where id='{token_claim['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
            "Session must exist in local auth.sessions")
    v2.expect(bc.get("user_metadata",{}).get("is_owner") is True,
              "Must challenge forged user-controlled metadata")
    packet=v2.packet()
    p_sources=packet["sources"]
    v2.denied(api,key,None,LOOKUP,{"p_sources":p_sources},"anonymous lookup")
    v2.denied(api,key,unbound,LOOKUP,{"p_sources":p_sources},"unbound signed lookup")
    v2.denied(api,key,unbound,FORK,{"p_packet":packet,"p_request_key":"unbound-fork-test-0001",
       "p_rationale":"Fictional separate author endeavor."},"unbound signed distinct create")
    first_args={"p_packet":packet,"p_request_key":"source-author-create-0001"}
    first=v2.accepted(api,key,author,v2.CREATE,first_args)
    pid=first["programId"]
    v2.expect(v2.accepted(api,key,author,v2.CREATE,first_args)["programId"]==pid,
              "Exact request retry must be idempotent")
    v2.expect([x["programId"] for x in get_matches(api,key,author,p_sources)]==[pid],
              "Author cannot recover first source Program")
    v2.expect(get_matches(api,key,other,p_sources)==[],
              "Other author's lookup revealed foreign draft")
    v2.rejected(api,key,author,v2.CREATE,
        {"p_packet":{**packet,"title":"Different display title"},
         "p_request_key":"source-author-create-0002"},"23505","duplicate sources")
    v2.denied(api,key,other,v2.READ,{"p_program_id":pid},"foreign Program UUID")
    v2.rejected(api,key,author,FORK,
        {**first_args,"p_request_key":"source-author-fork-short","p_rationale":"short"},
        "22023","short fork rationale")
    new_sources=[dict(x) for x in p_sources]
    new_sources[1]["sha256"]="c"*64
    altered={**packet,"sources":new_sources}
    saved=v2.accepted(api,key,author,v2.SAVE,{"p_program_id":pid,
         "p_expected_revision":1,"p_packet":altered,"p_request_key":"source-edit-0001"})
    v2.expect(saved["draftRevision"]==2,"Source edit must advance revision")
    v2.expect([x["programId"] for x in get_matches(api,key,author,p_sources)]==[pid],
              "Unapproved original source receipt was lost")
    v2.expect([x["programId"] for x in get_matches(api,key,author,new_sources)]==[pid],
              "Revised source receipt was not captured")
    rationale="A separately scoped fictional learning endeavor is intended."
    fork_args={"p_packet":packet,"p_request_key":"source-fork-0001","p_rationale":rationale}
    fork=v2.accepted(api,key,author,FORK,fork_args)
    fid=fork["programId"]
    v2.expect(fid!=pid and fork.get("distinctSourceDecisionRecorded") is True,
              "Deliberate fork must have distinct Program ID and receipt")
    v2.expect(v2.accepted(api,key,author,FORK,fork_args)["programId"]==fid,
              "Distinct retry created duplicate")
    v2.rejected(api,key,author,FORK,
        {**fork_args,"p_rationale":"A changed deliberately separate learning endeavor."},
        "23505","rewriting immutable fork rationale")
    v2.accepted(api,key,author,v2.SAVE,{"p_program_id":fid,"p_expected_revision":1,
       "p_packet":{**packet,"title":"New distinct instructions"},
       "p_request_key":"source-fork-edit-0001"})
    v2.rejected(api,key,author,v2.SAVE,{"p_program_id":fid,"p_expected_revision":2,
       "p_packet":altered,"p_request_key":"source-forbidden-cross-save"},
       "23505","overlapping existing source save")
    v2.expect({x["programId"] for x in get_matches(api,key,author,p_sources)}=={pid,fid},
              "Original and fork source match set incorrect")
    outsider=v2.accepted(api,key,other,v2.CREATE,
        {"p_packet":packet,"p_request_key":"source-other-create-0001"})
    v2.expect(outsider["programId"] not in (pid,fid),"Foreign create reused other author's ID")
    v2.expect([x["programId"] for x in get_matches(api,key,other,p_sources)]
              ==[outsider["programId"]],"Cross-author source match leaked data")
    v2.denied(api,key,other,v2.READ,{"p_program_id":fid},"private fork guessed UUID")
    v2.expect(auth.sql(a.db_url,
       "select count(*) from atlas.personal_program_author_distinct_import_decisions")=="1",
       "Fork decision table should contain one immutable result")
    v2.expect(auth.sql(a.db_url,
       "select count(*) from atlas.personal_program_author_source_receipts")=="4",
       "Expected four original/revised/fork/independent source receipts")
    auth.sql(a.db_url,f"""update atlas.personal_atlas_access_grants
       set state='revoked',revoked_at=now() where id='{v2.GRANT}'::uuid""")
    v2.denied(api,key,author,LOOKUP,{"p_sources":p_sources},
              "Revoked grant with still-valid JWT cannot look up source")
    v2.denied(api,key,author,FORK,{**fork_args,"p_request_key":"source-revoked-fork-0001"},
              "Revoked grant cannot deliberately fork")
    v2.denied(api,key,author,v2.SAVE,{"p_program_id":pid,"p_expected_revision":2,
       "p_packet":altered,"p_request_key":"source-revoked-save-0001"},
       "Revoked grant cannot save")
    v2.expect(len(get_matches(api,key,other,p_sources))==1,
              "Other author entitlement should remain functional")
    Path(a.output).parent.mkdir(parents=True,exist_ok=True)
    Path(a.output).write_text("PASS fictional signed A/B/unbound; durable source identity, fork and revoked grant\n")
    print("PASS genuine local GoTrue/PostgREST Program source identity")

if __name__=="__main__":
    main()
