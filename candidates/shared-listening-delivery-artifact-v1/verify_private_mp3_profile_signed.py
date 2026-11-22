#!/usr/bin/env python3
"""HELD signed local private MP3 profile source proof, disposable clone ONLY.

Reuses the existing native listening GoTrue/PostgREST helper on the original
protected clone. Real local signed JWTs, independent identities and session
revocation; NO production keys, source manuscript, audio, listener, publish or
migration release. Service-role key is LOCAL GoTrue fixture transport only.
"""
import argparse
import json
import os
from pathlib import Path
import re
import uuid
import verify_generated_listening_storage_signed as native

check=native.check
sql=native.sql
request=native.request
ok=native.ok
denied=native.denied
uid=native.uid
payload=native.payload
literal=native.literal

RPC="transcript_core_private_mp3_profile_self_api_v1"
EXPECTED={
    "schema":"transcript_core_private_mp3_delivery_profile_v1",
    "artifactRole":"listening_mp3","mimeType":"audio/mpeg",
    "codec":"libmp3lame","bitrate":"128k","channels":1,
    "sampleRate":48000,"publication_approved":False
}
MESSAGE=("PASS signed local native private MP3 profile: exact owner/editor, "
         "viewer/outsider/anonymous/service denial, idempotence, "
         "source conflict, revoked role/session; no media or publication.")

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(re.fullmatch(r"postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres",
                       args.db_url) is not None,"Disposable loopback Postgres only")
    for key in ("NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_DB_URL",
                "SUPABASE_ACCESS_TOKEN","SUPABASE_SERVICE_ROLE_KEY",
                "SUPABASE_SECRET_KEY"):
        check(not os.environ.get(key),"Hosted credential environment prohibited")
    api,pubkey,local_admin=native.local_status()
    db=args.db_url
    check(sql(db,"select count(*) from transcript_core.delivery_profiles")=="0",
          "Fresh schema-only clone without profile rows required")
    check(sql(db,"select count(*) from transcript_core.productions")=="0",
          "No copied real production records permitted")
    check(sql(db,"select has_function_privilege('authenticated',"
          "'public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)',"
          "'EXECUTE')")=="t","Authenticated current editor API missing")
    for role in ("anon","service_role"):
        check(sql(db,"select has_function_privilege("+literal(role)+","
              "'public.transcript_core_private_mp3_profile_self_api_v1(uuid,boolean)',"
              "'EXECUTE')")=="f","Unauthorized direct role execution grant")
    check(sql(db,"select has_table_privilege('authenticated',"
          "'transcript_core.delivery_profiles','SELECT')")=="f",
          "Private profile source table must not be client-readable")

    nonce=uuid.uuid4().hex
    actors={}
    for role in ("owner","editor","viewer","outsider"):
        email=f"private-mp3-{role}-{nonce}@example.invalid"
        password=uuid.uuid4().hex+"-Fixture!"
        u=json.loads(ok(request(api,local_admin,"/auth/v1/admin/users","POST",body={
             "email":email,"password":password,"email_confirm":True,
             "user_metadata":{"is_owner":role=="outsider"}}),"local fictional user"))
        user=uid(u["id"])
        signin=json.loads(ok(request(api,pubkey,"/auth/v1/token?grant_type=password",
             "POST",body={"email":email,"password":password}),"signed local session"))
        bearer=signin["access_token"]; claims=payload(bearer)
        session=uid(claims["session_id"])
        check(claims.get("role")=="authenticated" and uid(claims["sub"])==user
              and claims.get("is_anonymous") is False,
              "Real signed nonanonymous GoTrue identity required")
        identity=json.loads(ok(request(api,pubkey,"/auth/v1/user",token=bearer),
              "real local GoTrue bearer"))
        check(uid(identity["id"])==user,"Signed source principal mismatch")
        check(sql(db,"select count(*) from auth.sessions where id="+literal(session)+
             " and user_id="+literal(user))=="1",
             "Original persisted signed session missing")
        actors[role]={"user":user,"token":bearer,"session":session}
    check(len({v["user"] for v in actors.values()})==4,
          "Independent signed actor identities required")
    print("PASS four independent genuine local GoTrue sessions",flush=True)

    owner=actors["owner"]["token"]
    editor=actors["editor"]["token"]
    viewer=actors["viewer"]["token"]
    outsider=actors["outsider"]["token"]
    def rpc(name,body,token=owner):
        return request(api,pubkey,"/rest/v1/rpc/"+name,"POST",token,body)
    workspace=uid(json.loads(ok(rpc("transcript_core_create_workspace",
                  {"p_name":"Fictional profile validation workspace"}),
                  "signed owner native workspace")))
    for role in ("editor","viewer"):
        sql(db,"insert into transcript_core.workspace_memberships("
             "workspace_id,user_id,role) values("
             +literal(workspace)+","+literal(actors[role]["user"])+","+literal(role)+")")
    def profile(w=workspace,establish=False,token=owner):
        return rpc(RPC,{"p_workspace_id":w,"p_establish":establish},token)
    denied(profile(establish=False),"read of absent profile")
    denied(profile(establish=True,token=viewer),"viewer cannot create private profile")
    denied(profile(establish=False,token=viewer),"viewer cannot read private profile")
    denied(profile(establish=True,token=outsider),"outsider cannot create private profile")
    denied(profile(establish=False,token=outsider),"outsider cannot read private profile")
    denied(profile(establish=True,token=None),"anonymous cannot establish profile")
    denied(profile(establish=False,token=None),"anonymous cannot read private profile")
    denied(request(api,local_admin,"/rest/v1/rpc/"+RPC,"POST",body={
       "p_workspace_id":workspace,"p_establish":True}),
       "local service role cannot call user profile RPC")
    check(sql(db,"select count(*) from transcript_core.delivery_profiles")=="0",
          "Denied callers created private source records")

    first=json.loads(ok(profile(establish=True),"signed owner profile establishment"))
    same=json.loads(ok(profile(establish=True),"signed owner exact retry"))
    read=json.loads(ok(profile(),"signed owner profile read"))
    e_read=json.loads(ok(profile(token=editor),"signed editor exact read"))
    e_retry=json.loads(ok(profile(establish=True,token=editor),
                           "signed editor exact replay"))
    for receipt in (first,same,read,e_read,e_retry):
        check(receipt==first,"Source-issued profile receipt changed on replay")
    check(first=={
      "contractVersion":"transcript_core_private_mp3_profile_v1",
      "workspaceId":workspace,
      "profileId":first["profileId"],
      "profileKey":"private_audiobook_mp3",
      "ruleVersion":"native_private_mp3_v1",
      "configuration":EXPECTED,
      "publication_approved":False},
      "Source-owned fixed profile identity/configuration mismatch")
    uid(first["profileId"])
    check(sql(db,"select count(*) from transcript_core.delivery_profiles "
          "where workspace_id="+literal(workspace)+" and id="+
          literal(first["profileId"]))=="1","Only one exact source profile required")
    print("PASS signed writer, current editor, exact source-receipt replay",flush=True)

    # Existing but conflicting same version in a second, independently
    # owner-issued source workspace refuses overwrite or quiet substitution.
    foreign=uid(json.loads(ok(rpc("transcript_core_create_workspace",{
      "p_name":"Fictional incompatible profile workspace"}),
      "signed second source workspace")))
    sql(db,"insert into transcript_core.delivery_profiles("
        "workspace_id,profile_key,rule_version,display_name,configuration)"
        " values("+literal(foreign)+",'private_audiobook_mp3',"
        "'native_private_mp3_v1','Conflicting profile','{}'::jsonb)")
    denied(profile(foreign,True),"conflicting version refuses overwrite",
           expected=(400,401,403,404,409))
    denied(profile(foreign,False),"conflicting version refuses read",
           expected=(400,401,403,404,409))
    denied(profile(foreign,True,editor),"cross-workspace editor denies",
           expected=(400,401,403,404,409))
    check(sql(db,"select display_name from transcript_core.delivery_profiles "
          "where workspace_id="+literal(foreign))=="Conflicting profile",
          "Conflicting original profile was modified")

    # Independent source revocation: each old bearer was genuinely issued,
    # and an unexpired client-side token alone does not permit the operation.
    sql(db,"update transcript_core.workspace_memberships set role='viewer' "
           "where workspace_id="+literal(workspace)+" and user_id="+
           literal(actors["editor"]["user"]))
    denied(profile(token=editor),"former editor cannot read same profile")
    denied(profile(establish=True,token=editor),
           "former editor cannot rewrite same profile")
    sql(db,"delete from auth.sessions where id="+
           literal(actors["owner"]["session"])+" and user_id="+
           literal(actors["owner"]["user"]))
    denied(profile(token=owner),"revoked owner session cannot read profile")
    denied(profile(establish=True,token=owner),
           "revoked owner session cannot establish profile")
    denied(request(api,pubkey,"/auth/v1/user",token=owner),
           "revoked owner token rejected by GoTrue",expected=(401,403))
    check(sql(db,"select count(*) from transcript_core.delivery_profiles")=="2",
          "Revocation or denial changed source records")
    check(sql(db,"select count(*) from transcript_core.production_masters")=="0"
       and sql(db,"select count(*) from transcript_core.delivery_packages")=="0"
       and sql(db,"select count(*) from transcript_core.assets")=="0",
          "Profile proof unexpectedly created media/production custody")
    out=Path(args.output)
    out.write_text(MESSAGE+"\n",encoding="utf-8")
    print("PASS private versioned profile with genuine local signed role and session denials",flush=True)

if __name__=="__main__":
    main()
