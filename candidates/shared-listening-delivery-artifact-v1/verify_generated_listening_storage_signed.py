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

def diagnostic(data):
    # Do not echo response bodies, tokens, object paths or fixture identities.
    try:
        packet=json.loads(data)
    except (ValueError,UnicodeError):
        return "non-JSON error"
    if not isinstance(packet,dict):
        return "non-object error"
    terms=" ".join(str(packet.get(k,"")) for k in ("code","error","message","statusCode")).lower()
    categories=(("row-level security","RLS denial"),("permission denied","permission denial"),
                ("unauthorized","unauthorized"),("jwt","JWT rejected"),("bucket not found","bucket missing"),
                ("not found","not found"),("already exists","duplicate"),("duplicate","duplicate"),
                ("mime","MIME rejected"),("size","size rejected"),("invalid","invalid request"))
    code=packet.get("code")
    code=code if isinstance(code,str) and re.fullmatch(r"[A-Za-z0-9_]{1,40}",code) else "unavailable"
    return "code="+code+"; "+next((label for term,label in categories if term in terms),"unclassified error")

def ok(result, label):
    status,data=result
    check(200<=status<300, f"{label}: local HTTP {status}; {diagnostic(data)}")
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

def restore_native_storage_policy_parity(db):
    """Exact two already released policies (20260928200427), local only.

    The default schema dump excludes Supabase-managed storage schema.
    Preserve existing exact policies; never replace differing policies.
    Refuse if the expected RLS boundary or grants differ.
    """
    check(sql(db,"select relrowsecurity from pg_class where oid='storage.objects'::regclass")=="t",
          "Local Storage RLS must remain enabled")
    check(sql(db,"select has_table_privilege('authenticated','storage.objects','INSERT') and has_table_privilege('authenticated','storage.objects','SELECT')")=="t",
          "Existing authenticated Storage privileges required; no clone grants added")
    policies={
        "transcript_core_source_insert":("INSERT",None,
          "((bucket_id = ANY (ARRAY['transcript-core-observed-originals'::text, 'transcript-core-script-sources'::text])) AND transcript_core_can_workspace_edit(transcript_core_path_workspace(name)))",
          """create policy transcript_core_source_insert on storage.objects
             for insert to authenticated with check (
               bucket_id in ('transcript-core-observed-originals','transcript-core-script-sources')
               and public.transcript_core_can_workspace_edit(public.transcript_core_path_workspace(name)))"""),
        "transcript_core_asset_read":("SELECT",
          "((bucket_id = ANY (ARRAY['transcript-core-observed-originals'::text, 'transcript-core-observed-derivatives'::text, 'transcript-core-script-sources'::text, 'transcript-core-generated-takes'::text, 'transcript-core-generated-renders'::text])) AND transcript_core_is_workspace_member(transcript_core_path_workspace(name)))",None,
          """create policy transcript_core_asset_read on storage.objects
             for select to authenticated using (
               bucket_id in ('transcript-core-observed-originals','transcript-core-observed-derivatives',
                             'transcript-core-script-sources','transcript-core-generated-takes','transcript-core-generated-renders')
               and public.transcript_core_is_workspace_member(public.transcript_core_path_workspace(name)))""")}
    def read(name):
        return json.loads(sql(db,f"""select coalesce((select json_build_object(
              'cmd',cmd,'roles',roles,'permissive',permissive,'qual',qual,'with_check',with_check)
              from pg_policies where schemaname='storage' and tablename='objects' and policyname={literal(name)}),'null'::json)"""))
    for name,(cmd,qual,with_check,ddl) in policies.items():
        expected={"cmd":cmd,"roles":["authenticated"],"permissive":"PERMISSIVE","qual":qual,"with_check":with_check}
        current=read(name)
        if current is None:
            sql(db,ddl)
            current=read(name)
            print("RESTORED exact released clone policy "+name,flush=True)
        for k in ("qual","with_check"):
            if isinstance(current.get(k),str):
                current[k]=current[k].replace("public.","")
        check(current==expected,"Unexpected existing clone policy shape: "+name)
    print("PASS exact preexisting native Storage policy parity",flush=True)

# Existing Supabase Storage TUS endpoint. This is a signed local HTTP proof,
# not a generalized network client, SDK, worker or production uploader.
_TUS_CHUNK = 6 * 1024 * 1024

def tus_upload_local(api,key,bucket,name,data,token,mime):
    """Upload two or more real chunks with HEAD offset reconciliation.

    All requests stay on the CLI loopback gateway. The location is a
    server-issued token and is never sent to another origin.
    """
    base=urllib.parse.urlsplit(api)
    check(base.scheme=="http" and base.hostname=="127.0.0.1" and base.port==54321,
          "TUS may only contact disposable loopback gateway")
    check(isinstance(token,str) and len(token)>100 and 6*1024*1024<len(data)<=LIMIT,
          "TUS requires signed actor and bounded multi-chunk source")
    meta={"bucketName":bucket,"objectName":name,"contentType":mime,"cacheControl":"0"}
    encoded=",".join(k+" "+base64.b64encode(v.encode()).decode("ascii") for k,v in meta.items())
    shared={"apikey":key,"Authorization":"Bearer "+token,"Tus-Resumable":"1.0.0"}
    endpoint=api+"/storage/v1/upload/resumable"
    headers={**shared,"Upload-Length":str(len(data)),"Upload-Metadata":encoded,
             "x-upsert":"false","Content-Length":"0"}
    def call(url,method,body=None,extra=None):
        req=urllib.request.Request(url,data=body,headers={**shared,**(extra or {})},method=method)
        try:
            return OPENER.open(req,timeout=90)
        except urllib.error.HTTPError as exc:
            raise AssertionError("TUS "+method+" refused: HTTP "+str(exc.code)+
                                 "; "+diagnostic(exc.read(4096))) from None
    with call(endpoint,"POST",b"",headers) as initial:
        check(initial.status==201,"TUS creation did not return 201")
        location=initial.headers.get("Location")
    check(isinstance(location,str) and 0<len(location)<=4096,"Missing bounded TUS location")
    target=urllib.parse.urlsplit(urllib.parse.urljoin(api+"/",location))
    check(target.scheme=="http" and target.hostname=="127.0.0.1" and
          target.port==54321 and not target.username and not target.password and
          not target.query and not target.fragment and
          target.path.startswith("/storage/v1/upload/resumable/") and
          all(s not in ("",".","..") for s in target.path.split("/")[5:]),
          "Resumable location changed destination")
    upload_url=urllib.parse.urlunsplit(target)
    offset=0
    count=0
    while offset<len(data):
        chunk=data[offset:offset+_TUS_CHUNK]
        with call(upload_url,"PATCH",chunk,
                  {"Content-Type":"application/offset+octet-stream",
                   "Upload-Offset":str(offset)}) as response:
            check(response.status==204 and response.headers.get("Upload-Offset")==str(offset+len(chunk)),
                  "Signed TUS chunk offset mismatch")
        offset+=len(chunk); count+=1
        # Not just a simulated retry: reopen the actual current server-side
        # upload offset before continuing, as a resumed client would.
        if offset<len(data):
            with call(upload_url,"HEAD",extra={"Content-Length":"0"}) as head:
                check(head.status in (200,204) and
                      head.headers.get("Upload-Offset")==str(offset) and
                      head.headers.get("Upload-Length")==str(len(data)),
                      "Signed TUS resume offset mismatch")
    check(count>=2,"A multi-chunk real upload was not exercised")
    print("PASS actual signed TUS multi-chunk upload and HEAD resume",flush=True)

def trusted_signed_local_original_registration(db,api,key,token,workspace,obj_id,version,content):
    """Trusted disposable clone-only carrier invocation.

    Verify the real GoTrue bearer before installing its exact claims in one
    local protected Postgres transaction. No claim is accepted from a client
    payload; there is no production SQL connection or exposed RPC grant.
    This does NOT make a deployable privileged carrier.
    """
    response=json.loads(ok(request(api,key,"/auth/v1/user",token=token),"verified GoTrue bearer"))
    claims=payload(token)
    check(uid(response["id"])==uid(claims["sub"]) and
          claims.get("role")=="authenticated" and claims.get("is_anonymous") is False and
          uid(claims["session_id"]) and int(claims["exp"])>0,
          "GoTrue verified producer session required")
    check(sql(db,"select count(*) from auth.sessions where id="+literal(claims["session_id"])+
              " and user_id="+literal(claims["sub"]))=="1","Current native signed session required")
    h=digest(content)
    statement=("BEGIN;\n"
        "SELECT set_config('request.jwt.claims',"+literal(json.dumps(claims,separators=(",",":")))+",true) IS NOT NULL;\n"
        "SELECT set_config('request.jwt.claim.sub',"+literal(claims["sub"])+",true) IS NOT NULL;\n"
        "SELECT transcript_core.register_verified_manuscript_original_v1("
         +literal(workspace)+"::uuid,"+literal(obj_id)+"::uuid,"
         +literal(version)+","+literal(h)+","+str(len(content))+",'txt')::text;\n"
        "COMMIT;\n")
    # Send source-bound fixture claims over stdin, never command arguments or
    # files/artifacts. Any error message is categorized, never reproduced.
    out=subprocess.run(["psql",db,"-XAt","-v","ON_ERROR_STOP=1","-f","-"],
                       input=statement,capture_output=True,text=True)
    check(out.returncode==0,"Trusted local manuscript registration denied")
    receipts=[]
    for line in out.stdout.splitlines():
        if line.startswith('{"contractVersion"') or line.startswith('{"assetId"'):
            receipts.append(json.loads(line))
    check(len(receipts)==1 and receipts[0]["contractVersion"]==
          "transcript_core_verified_manuscript_original_v1" and
          receipts[0]["originalSha256"]==h and
          receipts[0]["objectId"]==obj_id and
          receipts[0]["objectVersion"]==version and
          receipts[0]["sourceFormat"]=="txt" and
          receipts[0]["publication_approved"] is False,
          "Original source registration receipt mismatch")
    return uid(receipts[0]["assetId"])

def trusted_signed_local_completion(db,api,key,token,intent,expected_denial=False):
    """Disposable-clone internal completion using a *verified* GoTrue user.

    All SQL is constructed from the test's own exact native source values.
    No browser-controlled SQL, hosted DB credentials, ordinary RPC privilege,
    service-role authority, or real production write is involved.
    """
    actual=json.loads(ok(request(api,key,"/auth/v1/user",token=token),"independent GoTrue completion bearer"))
    claims=payload(token)
    check(uid(actual["id"])==uid(claims["sub"]) and
          uid(claims["session_id"]) and claims["role"]=="authenticated" and
          claims.get("is_anonymous") is False and int(claims["exp"])>0,
          "Independently signed completion identity required")
    signature=["p_production_id","p_manuscript_revision_id","p_master_ordinal",
               "p_delivery_profile_id","p_profile_rule_version","p_profile_configuration",
               "p_timeline_manifest","p_evidence"]
    check(set(intent)==set(signature),"Exactly one canonical completion argument contract required")
    for item in (signature[0],signature[1],signature[3]):
        uid(intent[item])
    check(type(intent["p_master_ordinal"]) is int and 0<intent["p_master_ordinal"]<2147483648,
          "Exact source master ordinal required")
    stmt=("BEGIN;\n"
       "SELECT set_config('request.jwt.claims',"+literal(json.dumps(claims,separators=(",",":")))+",true) IS NOT NULL;\n"
       "SELECT set_config('request.jwt.claim.sub',"+literal(claims["sub"])+",true) IS NOT NULL;\n"
       "SELECT transcript_core.complete_verified_listening_production_v1("
       +literal(intent[signature[0]])+"::uuid,"+literal(intent[signature[1]])+"::uuid,"
       +str(intent[signature[2]])+","+literal(intent[signature[3]])+"::uuid,"
       +literal(intent[signature[4]])+","
       +literal(json.dumps(intent[signature[5]],sort_keys=True))+"::jsonb,"
       +literal(json.dumps(intent[signature[6]],sort_keys=True))+"::jsonb,"
       +literal(json.dumps(intent[signature[7]],sort_keys=True))+"::jsonb)::text;\n"
       "COMMIT;\n")
    run=subprocess.run(["psql",db,"-XAt","-v","ON_ERROR_STOP=1","-f","-"],
                      input=stmt,capture_output=True,text=True)
    if expected_denial:
        check(run.returncode!=0,"Unauthorized or conflicting native completion unexpectedly succeeded")
        return None
    check(run.returncode==0,"Trusted local internal production completion denied")
    values=[]
    for line in run.stdout.splitlines():
        if line.startswith('{"binding"') or line.startswith('{"contractVersion"'):
            values.append(json.loads(line))
    check(len(values)==1,"Exact one internal completion receipt required")
    return values[0]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--db-url",required=True)
    parser.add_argument("--output",required=True)
    args=parser.parse_args()
    check(re.fullmatch(r"postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url),
          "Disposable loopback database only")
    for k in ("NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_DB_URL",
              "SUPABASE_ACCESS_TOKEN","SUPABASE_SERVICE_ROLE_KEY","SUPABASE_SECRET_KEY"):
        check(not os.environ.get(k),"Hosted credential environment forbidden")
    api,key,admin=local_status()
    db=args.db_url
    check(sql(db,"select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'transcript_core_listening_render_%_v1'")=="4" and
          sql(db,"select count(*) from pg_policies where schemaname='storage' and tablename='objects' and policyname like 'transcript_core_manuscript_original_%_v1'")=="4",
          "Exact eight held listening and original Storage policies required")
    check(sql(db,"select has_function_privilege('authenticated','transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)','EXECUTE')")=="f",
          "Internal completion must remain unexposed")
    check(sql(db,"select count(*) from transcript_core.productions")=="0",
          "Fresh schema-only clone, without real production rows, required")
    restore_native_storage_policy_parity(db)
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
    check(rpc("transcript_core_can_workspace_edit",{"target_workspace":workspace}) is True,
          "Signed original owner must be native workspace editor")
    check(rpc("transcript_core_can_workspace_edit",{"target_workspace":workspace},actors["viewer"][1]) is False,
          "Signed viewer must lack native workspace edit authority")
    original=b"Fictional private manuscript for a transport proof."
    original_path=workspace+"/manuscript/"+digest(original)+".txt"
    def object_path(bucket,name,authenticated=False):
        return "/storage/v1/object/"+("authenticated/" if authenticated else "")+bucket+"/"+urllib.parse.quote(name,safe="/")
    def upload(bucket,name,data,token,mime,upsert=False):
        return request(api,key,object_path(bucket,name),"POST",token,data,mime,
                       {"x-upsert":"true" if upsert else "false"})
    def get(bucket,name,token):
        return request(api,key,object_path(bucket,name,True),token=token)
    ok(upload(SOURCE,original_path,original,owner,"text/plain"),"native original upload")
    check(ok(get(SOURCE,original_path,owner),"native original readback")==original,"Original byte mismatch")
    denied(get(SOURCE,original_path,actors["viewer"][1]),"viewer manuscript original read")
    denied(get(SOURCE,original_path,actors["outsider"][1]),"outsider manuscript original read")
    denied(upload(SOURCE,original_path,b"unapproved",actors["viewer"][1],"text/plain"),"viewer manuscript original insert")
    source_obj=json.loads(sql(db,"select json_build_object('id',id,'version',version)::text from storage.objects where bucket_id="+
                       literal(SOURCE)+" and name="+literal(original_path)))
    asset=trusted_signed_local_original_registration(db,api,key,owner,workspace,
                    uid(source_obj["id"]),source_obj["version"],original)
    check(sql(db,"select count(*) from transcript_core.assets where id="+literal(asset)+
                  " and provenance_class='manuscript_source' and storage_bucket="+literal(SOURCE)+
                  " and storage_path="+literal(original_path)+" and content_hash="+literal(digest(original)))=="1",
          "Native original was not registered as its actual authored source")
    check(trusted_signed_local_original_registration(db,api,key,owner,workspace,
                    uid(source_obj["id"]),source_obj["version"],original)==asset,
          "Original source registration changed on exact retry")
    print("PASS current signed GoTrue-bound internal native original registration and replay",flush=True)
    doc=uid(rpc("transcript_core_create_manuscript_document",{"p_workspace_id":workspace,"p_title":"Fictional manuscript"}))
    rev=uid(rpc("transcript_core_create_manuscript_revision",{"p_manuscript_document_id":doc,
        "p_content_hash":digest(original),"p_source_format":"txt","p_units":[{"sequence":1,"kind":"paragraph","text":original.decode()}],
        "p_source_asset_id":asset}))
    production=uid(rpc("transcript_core_create_production",{"p_workspace_id":workspace,"p_title":"Fictional production",
        "p_production_kind":"audiobook","p_source_kind":"manuscript_revision","p_source_revision_id":rev}))
    # Arbitrary fixture bytes deliberately exercise untrusted staging. Audio
    # validity is tested in Transcript Core and must not be inferred from MIME
    # or digest-shaped path here.
    master=b"transport proof master bytes; not valid audio"+b"."*(_TUS_CHUNK+19)
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
    tus_upload_local(api,key,BUCKET,master_path,master,owner,"audio/wav")
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
    # Exercise the actual native internal completion transaction, not an
    # ad hoc application table insert or an authenticated public RPC.
    profile_config={"format":"mp3","purpose":"fictional source-owned private listening proof"}
    profile_version="signed-test-profile-v1"
    profile=str(uuid.uuid4())
    sql(db,"insert into transcript_core.delivery_profiles("
        "id,workspace_id,profile_key,display_name,rule_version,configuration) values("
        +literal(profile)+"::uuid,"+literal(workspace)+"::uuid,"
        "'fictional-listening','Fictional listening test',"
        +literal(profile_version)+","+literal(json.dumps(profile_config))+"::jsonb)")
    intent={
        "p_production_id":production,
        "p_manuscript_revision_id":rev,
        "p_master_ordinal":1,
        "p_delivery_profile_id":profile,
        "p_profile_rule_version":profile_version,
        "p_profile_configuration":profile_config,
        "p_timeline_manifest":{"fixture":"actual private byte transfer; synthetic not-audio"},
        "p_evidence":{
            "original_object_id":uid(source_obj["id"]),
            "original_object_version":source_obj["version"],
            "original_sha256":digest(original),
            "original_byte_size":len(original),
            "extracted_sha256":digest(original),
            "intake_receipt_sha256":digest(b"fictional native intake receipt"),
            "master_object_id":before[master_path]["id"],
            "master_object_version":before[master_path]["version"],
            "master_sha256":digest(master),
            "master_byte_size":len(master),
            "mp3_object_id":before[mp3_path]["id"],
            "mp3_object_version":before[mp3_path]["version"],
            "mp3_sha256":digest(mp3),
            "mp3_byte_size":len(mp3),
            "export_receipt_sha256":digest(b"fictional native export receipt"),
            "export_id":digest(b"fictional selected export identity"),
            "publication_approved":False,
        }
    }
    check(sql(db,"select has_function_privilege('authenticated','transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)','EXECUTE')")=="f",
          "Native completion must not be a user RPC")
    # Denials cannot leave canonical objects because each invocation is
    # transaction-bound and rolls back when the internal function refuses.
    trusted_signed_local_completion(db,api,key,viewer,intent,expected_denial=True)
    mismatched=json.loads(json.dumps(intent))
    mismatched["p_evidence"]["mp3_object_version"]="stale-current-version"
    trusted_signed_local_completion(db,api,key,owner,mismatched,expected_denial=True)
    check(sql(db,"select count(*) from transcript_core.delivery_package_artifacts")=="0" and
          sql(db,"select count(*) from transcript_core.production_masters")=="0" and
          sql(db,"select count(*) from transcript_core.delivery_packages")=="0",
          "Rejected completion created an artifact")
    admitted=trusted_signed_local_completion(db,api,key,owner,intent)
    check(admitted.get("contractVersion")=="transcript_core_verified_listening_completion_v1"
          and admitted.get("productionId")==production
          and admitted.get("manuscriptRevisionId")==rev
          and admitted.get("publication_approved") is False
          and admitted.get("binding",{}).get("artifact_sha256")==digest(mp3)
          and admitted.get("binding",{}).get("publication_approved") is False,
          "Native private completion returned an incorrect receipt")
    check(trusted_signed_local_completion(db,api,key,owner,intent)==admitted,
          "Exact source native completion replay changed its receipt")
    conflicting=json.loads(json.dumps(intent))
    conflicting["p_evidence"]["export_receipt_sha256"]=digest(b"conflicting private export")
    trusted_signed_local_completion(db,api,key,owner,conflicting,expected_denial=True)
    check(sql(db,"select count(*) from transcript_core.production_masters")=="1" and
          sql(db,"select count(*) from transcript_core.delivery_packages")=="1" and
          sql(db,"select count(*) from transcript_core.delivery_package_artifacts")=="1" and
          sql(db,"select count(*) from transcript_core.assets where provenance_class='generated_render'")=="2",
          "Native admission did not preserve one master, one package and one bound derivative")
    print("PASS signed owner internal native fictional completion, replay, stale/foreign denial, no publication",flush=True)
    sql(db,f"update transcript_core.workspace_memberships set role='viewer' where workspace_id='{workspace}' and user_id='{actors['editor'][0]}'")
    denied(get(BUCKET,mp3_path,editor),"same bearer after role revocation")
    denied(upload(BUCKET,render(b'new','mp3'),b'new',editor,"audio/mpeg"),"revoked editor insertion")
    sql(db,f"delete from auth.sessions where id='{actors['owner'][2]}' and user_id='{actors['owner'][0]}'")
    denied(get(BUCKET,master_path,owner),"same bearer after session revocation")
    denied(get(SOURCE,original_path,owner),"same bearer manuscript original after session revocation")
    denied(upload(BUCKET,render(b'newer','wav'),b'newer',owner,"audio/wav"),"revoked owner insertion")
    check(sql(db,"select has_function_privilege('authenticated','transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)','EXECUTE')")=="f",
          "Internal manuscript registration must remain unexposed")
    # A revoked GoTrue session cannot authenticate a further completion at
    # all. The earlier signed transaction proved internal native completion;
    # now assert the independently signed bearer is rejected before a trusted
    # caller could install claims. Do not force a revoked user into SQL.
    denied(request(api,key,"/auth/v1/user",token=owner),
           "revoked producer cannot authenticate to initiate completion",
           expected=(401,403))
    check(sql(db,"select count(*) from auth.sessions where id="+literal(actors["owner"][2])+
                  " and user_id="+literal(actors["owner"][0]))=="0",
          "Revoked owner session unexpectedly persisted")
    check(sql(db,"select count(*) from transcript_core.delivery_package_artifacts")=="1" and
          sql(db,"select count(*) from transcript_core.production_masters")=="1" and
          sql(db,"select count(*) from transcript_core.delivery_packages")=="1" and
          sql(db,"select count(*) from transcript_core.assets where provenance_class='generated_render'")=="2",
          "Revoked or conflicting completion changed native private custody")
    Path(args.output).write_text("PASS signed local Storage and manuscript-original proof; bounded private native completion, replay and revocation denials; no publication.\n")
if __name__=="__main__":
    main()
