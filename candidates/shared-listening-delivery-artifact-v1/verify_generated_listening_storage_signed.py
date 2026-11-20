#!/usr/bin/env python3
"""HELD disposable clone probe: real local GoTrue and Storage HTTP.

Requires the reviewed completion + staging candidates in a schema-only
Supabase clone, never production. Tests actual transferred synthetic bytes,
not audio quality or the future privileged receipt-completion carrier.
Uses no hosted key. No listener entitlement, publication, or release.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

BUCKET = "transcript-core-generated-renders"
SOURCE = "transcript-core-script-sources"
LIMIT = 8 * 1024 * 1024
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

def check(condition, message):
    if not condition:
        raise AssertionError(message)

def sql(db, statement):
    return subprocess.run(["psql", db, "-XAt", "-v", "ON_ERROR_STOP=1", "-c", statement],
                          capture_output=True, text=True, check=True).stdout.strip()

def local_status():
    raw = subprocess.run(["supabase", "status", "-o", "env"], capture_output=True,
                         text=True, check=True).stdout
    values = dict(line.split("=",1) for line in raw.splitlines() if "=" in line)
    vals = {k.strip():v.strip().strip('"') for k,v in values.items()}
    api = vals.get("API_URL", "").rstrip("/")
    parsed = urllib.parse.urlparse(api)
    check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1" and
          parsed.port == 54321 and not parsed.path and not parsed.query and
          not parsed.username and not parsed.password, "Default disposable local API required")
    check(vals.get("ANON_KEY") and vals.get("SERVICE_ROLE_KEY"), "Local CLI fixture keys required")
    return api, vals["ANON_KEY"], vals["SERVICE_ROLE_KEY"]

def request(api, key, path, method="GET", token=None, body=None, mime="application/json",
            headers=None):
    check(path.startswith(("/auth/v1/", "/storage/v1/", "/rest/v1/rpc/")), "Unexpected local API path")
    h = {"apikey":key,"Authorization":"Bearer "+(token or key),"Content-Type":mime}
    if headers:
        h.update(headers)
    if isinstance(body,dict):
        body=json.dumps(body).encode()
    req = urllib.request.Request(api+path,data=body,headers=h,method=method)
    try:
        with OPENER.open(req,timeout=60) as response:
            data=response.read(LIMIT+1)
            check(len(data)<=LIMIT,"Unexpected unbounded response")
            return response.status,data
    except urllib.error.HTTPError as exc:
        return exc.code,exc.read(4096)

def ok(result, label):
    status,data=result
    check(200<=status<300, f"{label}: local HTTP {status}")
    return data

def denied(result,label,expected=(400,401,403,404)):
    status,_=result
    check(status in expected,f"{label}: expected denial, got local HTTP {status}")
    print("PASS "+label,flush=True)

def payload(token):
    b=token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(b+"="*(-len(b)%4)))

def uid(v):
    return str(uuid.UUID(v))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def literal(v):
    return "'"+str(v).replace("'","''")+"'"

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(args.db_url=="postgresql://postgres:postgres@127.0.0.1:54322/postgres",
          "Default disposable local database only")
    for k in ("NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_DB_URL",
              "SUPABASE_ACCESS_TOKEN","SUPABASE_SERVICE_ROLE_KEY","SUPABASE_SECRET_KEY"):
        check(not os.environ.get(k),"Hosted credential environment forbidden")
    api,key,admin=local_status()
    db=args.db_url
    check(sql(db,"select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'transcript_core_listening_render_%_v1'")=="4",
          "Exact four held storage policies required")
    check(sql(db,"select has_function_privilege('authenticated','transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)','EXECUTE')")=="f",
          "Internal completion must remain unexposed")
    check(sql(db,"select count(*) from transcript_core.productions")=="0",
          "Fresh schema-only clone, without real production rows, required")
    # Buckets are metadata, not application records. The schema-only clone
    # may omit them; seed only the native private test buckets locally.
    for bucket in (BUCKET,SOURCE):
        sql(db,f"insert into storage.buckets(id,name,public) values({literal(bucket)},{literal(bucket)},false) on conflict(id) do nothing")
        check(sql(db,f"select public is false from storage.buckets where id={literal(bucket)}")=="t","Private local bucket required")
    # GoTrue creates independent synthetic local users and signs sessions; no
    # fabricated claims, production account, real mailbox or secret output.
    actors={}
    nonce=uuid.uuid4().hex
    for role in ("owner","editor","viewer","outsider"):
        email=f"listening-{role}-{nonce}@example.invalid"
        password=uuid.uuid4().hex+"-Fixture!"
        created=json.loads(ok(request(api,admin,"/auth/v1/admin/users","POST",body={
            "email":email,"password":password,"email_confirm":True,
            "user_metadata":{"is_owner":role=="outsider"}}),"local fixture user"))
        person=uid(created["id"])
        session=json.loads(ok(request(api,key,"/auth/v1/token?grant_type=password","POST",
                                      body={"email":email,"password":password}),"signed local session"))
        token=session["access_token"]; claims=payload(token); sid=uid(claims["session_id"])
        check(claims.get("role")=="authenticated" and uid(claims["sub"])==person,
              "Unexpected signed actor")
        actual=json.loads(ok(request(api,key,"/auth/v1/user",token=token),"GoTrue bearer verification"))
        check(uid(actual["id"])==person,"Signed actor mismatch")
        check(sql(db,f"select count(*) from auth.sessions where id='{sid}' and user_id='{person}'")=="1",
              "Persisted session required")
        actors[role]=(person,token,sid)
    check(len({a[0] for a in actors.values()})==4,"Independent actors required")
    print("PASS independently signed owner, editor, viewer and outsider",flush=True)
    owner=actors["owner"][1]
    def rpc(name,body,token=owner):
        return json.loads(ok(request(api,key,"/rest/v1/rpc/"+name,"POST",token,body),name))
    workspace=uid(rpc("transcript_core_create_workspace",{"p_name":"Fictional listening proof"}))
    for role in ("editor","viewer"):
        sql(db,f"insert into transcript_core.workspace_memberships(workspace_id,user_id,role) values('{workspace}','{actors[role][0]}','{role}')")
    original=b"Fictional private manuscript for a transport proof."
    original_path=workspace+"/fixture-original.txt"
    def object_path(bucket,name,authenticated=False):
        return "/storage/v1/object/"+("authenticated/" if authenticated else "")+bucket+"/"+urllib.parse.quote(name,safe="/")
    def upload(bucket,name,data,token,mime,upsert=False):
        return request(api,key,object_path(bucket,name),"POST",token,data,mime,
                       {"x-upsert":"true" if upsert else "false"})
    def get(bucket,name,token):
        return request(api,key,object_path(bucket,name,True),token=token)
    ok(upload(SOURCE,original_path,original,owner,"text/plain"),"native original upload")
    check(ok(get(SOURCE,original_path,owner),"native original readback")==original,"Original byte mismatch")
    # Clone-only source fixture, since generated-manuscript original
    # registration is outside this storage-policy proof. No fake observed
    # recording, script parsing job, or production registry.
    asset=uid(sql(db,f"""insert into transcript_core.assets(workspace_id,provenance_class,storage_bucket,storage_path,content_hash,mime_type,byte_size)
          values('{workspace}','script_source','{SOURCE}',{literal(original_path)},'{digest(original)}','text/plain',{len(original)}) returning id""").splitlines()[0])
    doc=uid(rpc("transcript_core_create_manuscript_document",{"p_workspace_id":workspace,"p_title":"Fictional manuscript"}))
    rev=uid(rpc("transcript_core_create_manuscript_revision",{"p_manuscript_document_id":doc,
        "p_content_hash":digest(original),"p_source_format":"txt","p_units":[{"sequence":1,"kind":"paragraph","text":original.decode()}],
        "p_source_asset_id":asset}))
    production=uid(rpc("transcript_core_create_production",{"p_workspace_id":workspace,"p_title":"Fictional production",
        "p_production_kind":"audiobook","p_source_kind":"manuscript_revision","p_source_revision_id":rev}))
    # Arbitrary fixture bytes deliberately exercise untrusted staging. Audio
    # validity is tested in Transcript Core and must not be inferred from MIME
    # or digest-shaped path here.
    master=b"transport proof master bytes; not valid audio"
    mp3=b"transport proof derivative bytes; not valid audio"
    def render(data,suffix,p=production,w=workspace):
        return f"{w}/{p}/listening/{digest(data)}.{suffix}"
    master_path,mp3_path=render(master,"wav"),render(mp3,"mp3")
    editor=actors["editor"][1]; viewer=actors["viewer"][1]; outsider=actors["outsider"][1]
    denied(upload(BUCKET,master_path,master,viewer,"audio/wav"),"viewer insert")
    denied(upload(BUCKET,master_path,master,outsider,"audio/wav"),"outsider insert despite claimed user metadata")
    denied(upload(BUCKET,master_path,master,None,"audio/wav"),"anonymous insert")
    denied(upload(BUCKET,render(master,"wav",p=str(uuid.uuid4())),master,owner,"audio/wav"),"unknown production")
    denied(upload(BUCKET,render(master,"wav",w=str(uuid.uuid4())),master,owner,"audio/wav"),"wrong workspace")
    denied(upload(BUCKET,workspace+"/"+production+"/listening/not-a-hash.wav",master,owner,"audio/wav"),"malformed path")
    ok(upload(BUCKET,master_path,master,owner,"audio/wav"),"signed owner upload")
    ok(upload(BUCKET,mp3_path,mp3,editor,"audio/mpeg"),"signed editor upload")
    def state(name):
        row=sql(db,f"select json_build_object('id',id,'version',version,'size',metadata->>'size','mime',metadata->>'mimetype')::text from storage.objects where bucket_id='{BUCKET}' and name={literal(name)}")
        obj=json.loads(row)
        check(uid(obj["id"]) and obj["version"],"Missing actual immutable object version")
        return obj
    before={master_path:state(master_path),mp3_path:state(mp3_path)}
    for name,data,mime in ((master_path,master,"audio/wav"),(mp3_path,mp3,"audio/mpeg")):
        check(before[name]["size"]==str(len(data)) and before[name]["mime"]==mime,"Actual object metadata mismatch")
        check(ok(get(BUCKET,name,owner),"signed owner readback")==data,"Owner byte mismatch")
        check(ok(get(BUCKET,name,editor),"signed editor readback")==data,"Editor byte mismatch")
        denied(get(BUCKET,name,viewer),"viewer read")
        denied(get(BUCKET,name,outsider),"outsider read")
        denied(get(BUCKET,name,None),"anonymous private read")
        denied(upload(BUCKET,name,b"replacement",owner,mime,True),"upsert blocked",expected=(400,401,403,409))
        denied(upload(BUCKET,name,b"replacement",owner,mime,False),"duplicate path blocked",expected=(400,401,403,409))
        check(state(name)==before[name],"Storage object identity or version changed")
        check(ok(get(BUCKET,name,owner),"original readback after denied replacement")==data,"Bytes overwritten")
    # Real HTTP delete, API may return a success-shaped no-op for an RLS-hidden
    # object. Prove unchanged metadata and bytes rather than assume status.
    status,_=request(api,key,object_path(BUCKET,master_path),"DELETE",owner)
    check(status in (200,204,400,401,403,404),"Unexpected delete status")
    check(state(master_path)==before[master_path] and ok(get(BUCKET,master_path,owner),"post-delete readback")==master,
          "Authenticated deletion changed the custody object")
    print("PASS actual signed uploads, exact byte readback, object version and replacement/delete denial",flush=True)
    sql(db,f"update transcript_core.workspace_memberships set role='viewer' where workspace_id='{workspace}' and user_id='{actors['editor'][0]}'")
    denied(get(BUCKET,mp3_path,editor),"same bearer after role revocation")
    denied(upload(BUCKET,render(b'new','mp3'),b'new',editor,"audio/mpeg"),"revoked editor insertion")
    sql(db,f"delete from auth.sessions where id='{actors['owner'][2]}' and user_id='{actors['owner'][0]}'")
    denied(get(BUCKET,master_path,owner),"same bearer after session revocation")
    denied(upload(BUCKET,render(b'newer','wav'),b'newer',owner,"audio/wav"),"revoked owner insertion")
    check(sql(db,"select count(*) from transcript_core.delivery_package_artifacts")=="0" and
          sql(db,"select count(*) from transcript_core.production_masters")=="0" and
          sql(db,"select count(*) from transcript_core.delivery_packages")=="0" and
          sql(db,"select count(*) from transcript_core.assets where provenance_class='generated_render'")=="0",
          "Unverified upload incorrectly admitted canonical production")
    Path(args.output).write_text("PASS signed local Storage staging and byte readback; independent denials; no admission or publication.\n")
if __name__=="__main__":
    main()
