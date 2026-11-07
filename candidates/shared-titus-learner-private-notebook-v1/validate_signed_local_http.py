#!/usr/bin/env python3
"""HELD. Genuine local GoTrue OAuth 2.1 + PostgREST private-note admission proof.

Runs ONLY with a disposable localhost Supabase stack and fictional learners.
Never modifies production, never forges JWTs, and never logs bearer tokens.
"""
import argparse,base64,hashlib,importlib.util,json,re,secrets,subprocess,urllib.error
import urllib.parse,urllib.request,uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SPEC=importlib.util.spec_from_file_location("c1",ROOT/"scripts/validate-atlas-c1-signed-http.py")
c1=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(c1)
CLIENT="d0b999e7-a2e2-4bb8-91ea-482fcd44b257"
OFFERING="aa000000-0000-4000-8000-000000000001"
ENROLL=("bb000000-0000-4000-8000-000000000001","bb000000-0000-4000-8000-000000000002")
COURSE="80000000-0000-4000-8000-000000000001"
VERSION="90000000-0000-4000-8000-000000000001"
LEDGER="60000000-0000-4000-8000-000000000001"
ACTIVATION="70000000-0000-4000-8000-000000000001"
PASSWORD="Fictional-only-local-Titus-signed-2026!"
REDIRECT="http://127.0.0.1:54321/oauth/callback"
ORIGIN="http://127.0.0.1:3000"
UUID=re.compile(r"^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$",re.I)

def check(good,reason):
 if not good:raise AssertionError(reason)
def db(q):
 return c1.sql(ARGS.db_url,q)
def http(method,url,key,token=None,body=None,origin=None,follow=False,form=False):
 p=urllib.parse.urlsplit(url)
 check(p.scheme=="http" and p.hostname in ("127.0.0.1","localhost") and p.port in (3000,54321),
       "Refusing nonlocal HTTP address")
 raw=None
 headers={"apikey":key,"Accept":"application/json"}
 if token:headers["Authorization"]="Bearer "+token
 if origin:headers["Origin"]=origin
 if body is not None:
  if form:
   raw=urllib.parse.urlencode(body).encode()
   headers["Content-Type"]="application/x-www-form-urlencoded"
  else:
   raw=json.dumps(body).encode()
   headers["Content-Type"]="application/json"
 class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self,req,fp,code,msg,hdrs,newurl):return None
 opener=urllib.request.build_opener() if follow else urllib.request.build_opener(NoRedirect)
 req=urllib.request.Request(url,data=raw,headers=headers,method=method)
 try:
  with opener.open(req,timeout=25) as res:
   content=res.read().decode()
   return res.status,json.loads(content) if content else None,res.headers.get("Location")
 except urllib.error.HTTPError as err:
  content=err.read().decode()
  try:result=json.loads(content)
  except ValueError:result={"error":"not_json"}
  return err.code,result,err.headers.get("Location")
def rpc(api,key,token,name,data):
 code,payload,_=http("POST",api+"/rest/v1/rpc/"+name,key,token,data)
 return code,payload
def deny(api,key,token,name,data,context):
 status,answer=rpc(api,key,token,name,data)
 check(status in (401,403) and isinstance(answer,dict) and
       (token is None or answer.get("code")=="42501" or answer.get("code")=="PGRST301"),
       f"{context}: denied with source or transport permission, got HTTP {status} code {answer.get('code') if isinstance(answer,dict) else ''}")
 print("PASS",context)
def success(api,key,token,name,data):
 status,obj=rpc(api,key,token,name,data)
 check(status==200 and isinstance(obj,dict) and obj.get("state")=="ready",
       f"{name} failed HTTP {status} ({obj.get('code') if isinstance(obj,dict) else ''})")
 return obj
def note_args(enrollment,request=None,body="Fictional notebook original"):
 return {"p_enrollment_id":enrollment,"p_request_id":request or str(uuid.uuid4()),"p_body_text":body}
def read_args(enrollment):
 return {"p_enrollment_id":enrollment}
def admin_user(api,key,service,label):
 address=f"titus-held-{label}@example.invalid"
 status,obj,_=http("POST",api+"/auth/v1/admin/users",key,service,
                   {"email":address,"password":PASSWORD,"email_confirm":True})
 check(status in (200,201) and isinstance(obj,dict) and UUID.fullmatch(obj.get("id","")),
       f"Local synthetic GoTrue user {label} not created (HTTP {status})")
 return obj["id"],address
def ordinary_token(api,key,address):
 code,payload,_=http("POST",api+"/auth/v1/token?grant_type=password",key,
                      body={"email":address,"password":PASSWORD})
 check(code==200 and isinstance(payload,dict) and payload.get("access_token"),
       f"Local ordinary GoTrue session unavailable HTTP {code}")
 token=payload["access_token"]
 claims=c1.jwt_payload(token)
 check(claims.get("session_id") and claims.get("role")=="authenticated",
       "GoTrue did not issue a signed session")
 return token,claims
def oauth_client(api,key,service):
 code,obj,_=http("POST",api+"/auth/v1/admin/oauth/clients",key,service,{
  "client_name":"Held Titus notebook local proof","redirect_uris":[REDIRECT],
  "client_type":"public","token_endpoint_auth_method":"none"
 })
 check(code in (200,201) and isinstance(obj,dict) and UUID.fullmatch(obj.get("client_id","")),
       f"Local OAuth client not registered HTTP {code}: {obj.get('code') if isinstance(obj,dict) else ''}")
 generated=obj["client_id"]
 # One fixed existing Titus client ID, only in this disposable local database.
 # The candidate itself is never rewritten for test admission.
 table=db("SELECT coalesce(to_regclass('auth.oauth_clients')::text,'')")
 check(table=="auth.oauth_clients","Local GoTrue OAuth client table not present; no token fabrication fallback")
 check(db(f"WITH rebound AS (UPDATE auth.oauth_clients SET id='{CLIENT}' WHERE id='{generated}' RETURNING id) SELECT id FROM rebound") == CLIENT,
       "Local OAuth client ID could not be bound to exact existing Titus issuer")
 return CLIENT
def oauth_token(api,key,plain,client_id=CLIENT):
 verifier=secrets.token_urlsafe(48)
 challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")
 state=secrets.token_urlsafe(24)
 q=urllib.parse.urlencode({
  "client_id":client_id,"redirect_uri":REDIRECT,"response_type":"code",
  "code_challenge":challenge,"code_challenge_method":"S256","state":state,"scope":"email"
 })
 code,_,location=http("GET",api+"/auth/v1/oauth/authorize?"+q,key)
 check(code==302 and location,"OAuth authorize did not redirect to local consent")
 u=urllib.parse.urlsplit(location)
 check(u.hostname in ("127.0.0.1","localhost") and
       u.path.endswith("/oauth/consent"),"Consent redirect not local/recognized")
 authorization_id=urllib.parse.parse_qs(u.query).get("authorization_id",[None])[0]
 check(authorization_id and re.fullmatch(r"[A-Za-z0-9_-]{12,256}",authorization_id),
       "GoTrue authorization ID not issued as a bounded opaque token")
 endpoint=api+"/auth/v1/oauth/authorizations/"+authorization_id
 code,details,_=http("GET",endpoint,key,plain,origin=ORIGIN)
 check(code==200 and isinstance(details,dict) and
       (details.get("authorization_id")==authorization_id or details.get("redirect_url")),
       "Signed local learner cannot inspect own OAuth authorization")
 if "redirect_url" in details:
  url=details["redirect_url"]
 else:
  code,out,_=http("POST",endpoint+"/consent",key,plain,
                  {"action":"approve"},origin=ORIGIN)
  check(code==200 and isinstance(out,dict) and out.get("redirect_url"),
        "Local learner OAuth consent not granted")
  url=out["redirect_url"]
 target=urllib.parse.urlsplit(url)
 check(target.hostname=="127.0.0.1" and target.port==54321 and
       target.path=="/oauth/callback","Unapproved OAuth callback")
 params=urllib.parse.parse_qs(target.query)
 check(params.get("state")==[state] and "code" in params,"OAuth authorization state/code mismatch")
 code,payload,_=http("POST",api+"/auth/v1/oauth/token",key,
                   body={"grant_type":"authorization_code","code":params["code"][0],
                         "client_id":client_id,"redirect_uri":REDIRECT,"code_verifier":verifier},form=True)
 check(code==200 and isinstance(payload,dict) and payload.get("access_token"),
       f"Local GoTrue OAuth token exchange failed HTTP {code}")
 token=payload["access_token"]
 claims=c1.jwt_payload(token)
 check(claims.get("client_id")==client_id and claims.get("session_id"),
       "GoTrue OAuth did not cryptographically issue the requested client claim")
 check(UUID.fullmatch(claims.get("sub","")),"OAuth token has no signed Person sub")
 return token,claims
def seed_person(user_id,i):
 person=f"30000000-0000-4000-8000-{i:012d}"
 binding=f"40000000-0000-4000-8000-{i:012d}"
 cred=f"50000000-0000-4000-8000-{i:012d}"
 db(f"""INSERT INTO reality.entities(id,stable_key,display_name,entity_kind,identity_state)
 VALUES ('{person}','held_fictional_person_{i}','Fictional Learner or Governing Teacher {i}',
         'person','canonical');
 INSERT INTO reality.auth_person_bindings
  (id,auth_user_id,person_entity_id,binding_state)
  VALUES ('{binding}','{user_id}','{person}','active');
 INSERT INTO atlas.people(id,stable_key,display_name,status)
  VALUES ('{person}','held_titus_learner_{i}','Fictional Atlas Person {i}','active');
 INSERT INTO atlas.person_auth_credentials
  (id,person_id,credential_kind,auth_user_id,status)
  VALUES ('{cred}','{person}','supabase_auth_user','{user_id}','active');""")
 if i==3:
  principal="31000000-0000-4000-8000-000000000003"
  db(f"""INSERT INTO atlas.principals
    (id,user_id,person_id,stable_key,name,status)
   VALUES ('{principal}','{user_id}','{person}',
    'held_fictional_teaching_governor','Fictional Teacher/Governor','active');""")
 return person
def seed_enrollment(people):
 # A genuinely linked fictional principal governs a fictional Ledger and
 # publishes one Teaching Course Version before two distinct learner enrollments.
 # This mirrors the source-shaped FK and capability activation relations; it is
 # NOT the actual protected Noel production schema/trigger/release test.
 principal="31000000-0000-4000-8000-000000000003"
 governor=people[2]
 db(f"""INSERT INTO atlas.ledgers(id,stable_key,name,ledger_kind,status)
   VALUES ('{LEDGER}','held_titus_fictional_ledger','Held Titus Fictional Teaching Ledger',
           'governed_reality','active');
 INSERT INTO atlas.principal_ledger_authorities
   (id,principal_id,ledger_id,authority_kind,status,basis)
 VALUES ('32000000-0000-4000-8000-000000000003','{principal}','{LEDGER}',
         'root_governing','active','local_titus_private_notebook_test');
 INSERT INTO atlas.capability_definitions
   (capability_key,capability_version,status,eligible_subject_kinds)
 VALUES ('teaching',1,'active',ARRAY['ledger']::text[]);
 INSERT INTO atlas.capability_activations
   (id,ledger_id,capability_key,capability_version,subject_ledger_id,
    subject_kind,subject_id,state,created_by_person_id,created_by_principal_id)
 VALUES ('{ACTIVATION}','{LEDGER}','teaching',1,'{LEDGER}',
         'ledger','{LEDGER}','active','{governor}','{principal}');
 INSERT INTO atlas.teaching_courses
   (id,ledger_id,capability_activation_id,course_key,name,status,
    created_by_person_id,created_by_principal_id)
 VALUES ('{COURSE}','{LEDGER}','{ACTIVATION}',
         'held_fictional_course_101','Held Fictional Course 101','active',
         '{governor}','{principal}');
 INSERT INTO atlas.teaching_course_versions
   (id,course_id,version_no,title,published_by_person_id,published_by_principal_id,
    published_at)
 VALUES ('{VERSION}','{COURSE}',1,'Held Fictional Course v1',
         '{governor}','{principal}',now());
 INSERT INTO atlas.teaching_course_offerings
   (id,ledger_id,course_id,course_version_id,state,opened_at,delivery_mode,
    created_by_person_id,created_by_principal_id)
 VALUES ('{OFFERING}','{LEDGER}','{COURSE}','{VERSION}',
         'open',now(),'cohort','{governor}','{principal}');
 INSERT INTO atlas.teaching_enrollments
   (id,ledger_id,offering_id,person_id,state,enrolled_by_person_id,enrolled_by_principal_id)
 VALUES ('{ENROLL[0]}','{LEDGER}','{OFFERING}','{people[0]}',
         'active','{governor}','{principal}'),
        ('{ENROLL[1]}','{LEDGER}','{OFFERING}','{people[1]}',
         'active','{governor}','{principal}');""")
 check(db(f"SELECT atlas.teaching_activation_active_v1('{LEDGER}'::uuid,'{ACTIVATION}'::uuid)")=="t",
       "Real source-defined governed Teaching activation did not allow fixture")
 # Strong negative: teacher has actual fictional Ledger authority, but no
 # Enrollment as the learner Person, and thus receives no private-note reader.
 check(db(f"SELECT count(*) FROM atlas.principal_ledger_authorities WHERE principal_id='{principal}' AND ledger_id='{LEDGER}' AND status='active'")=="1",
       "Governing teacher authority fixture missing")
def main():
 global ARGS
 ap=argparse.ArgumentParser()
 ap.add_argument("--db-url",required=True)
 ap.add_argument("--output",required=True)
 ARGS=ap.parse_args()
 check(bool(re.fullmatch(r"postgres(?:ql)?://[^@]+@127[.]0[.]0[.]1:[0-9]+/postgres",ARGS.db_url)),
       "Refuse nonlocal DB")
 api,key=c1.local_status()
 # Only local status; SUPABASE_SERVICE_ROLE_KEY/ SERVICE_ROLE_KEY never logged.
 result=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=True)
 values=dict(x.split("=",1) for x in result.stdout.splitlines() if "=" in x)
 service=(values.get("SERVICE_ROLE_KEY") or values.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip().strip('"')
 check(bool(service),"Local scratch service key unavailable")
 oauth_client(api,key,service)
 users=[admin_user(api,key,service,label) for label in ("one","two","outsider")]
 people=[seed_person(uid,i) for i,(uid,address) in enumerate(users,1)]
 seed_enrollment(people)
 db("NOTIFY pgrst, 'reload schema';")
 signed=[]
 ordinary=[]
 for uid,address in users:
  base,base_claims=ordinary_token(api,key,address)
  check(base_claims.get("sub")==uid,"Local ordinary session bound to wrong Auth user")
  ordinary.append(base)
  oauth,claims=oauth_token(api,key,base)
  check(claims.get("sub")==uid,"OAuth learner wrong Auth identity")
  check(db(f"select count(*) from auth.sessions where id='{claims['session_id']}'::uuid and user_id='{uid}'::uuid")=="1",
        "Signed OAuth session not registered in local GoTrue database")
  signed.append((oauth,claims))
 print("PASS three real local GoTrue OAuth2.1 PKCE sessions with canonical Titus client")
 create="titus_learner_private_note_create_self_api_v1"
 read="titus_learner_private_notes_read_self_api_v1"
 a,b,outs=(item[0] for item in signed)
 check(success(api,key,a,read,read_args(ENROLL[0]))["notes"]==[],
       "Learner's notebook initially empty")
 req=str(uuid.uuid4())
 first=success(api,key,a,create,note_args(ENROLL[0],req))
 check(first.get("replay") is False,"New original must not be replay")
 again=success(api,key,a,create,note_args(ENROLL[0],req))
 check(again.get("noteId")==first.get("noteId") and again.get("replay") is True,
       "Idempotent original replay changed")
 notes=success(api,key,a,read,read_args(ENROLL[0]))["notes"]
 check(len(notes)==1 and notes[0]["body"]=="Fictional notebook original",
       "Signed learner cannot reopen exact private original")
 deny(api,key,b,read,read_args(ENROLL[0]),"Other enrolled learner read denied")
 deny(api,key,b,create,note_args(ENROLL[0]),"Other enrolled learner write denied")
 deny(api,key,outs,read,read_args(ENROLL[0]),"Teacher/outsider read denied")
 deny(api,key,outs,create,note_args(ENROLL[0]),"Teacher/outsider write denied")
 deny(api,key,ordinary[0],read,read_args(ENROLL[0]),"Genuine password JWT without Titus client denied")
 deny(api,key,None,read,read_args(ENROLL[0]),"Anonymous reader denied")
 deny(api,key,a,read,read_args(str(uuid.uuid4())),"Unknown enrollment denied")
 # Genuinely distinct OAuth sessions; a correct duplicate concurrent write must
 # create exactly one original, with a successful replay.
 second,sc=oauth_token(api,key,ordinary[0])
 check(sc.get("session_id")!=signed[0][1].get("session_id"),
       "Concurrency proof requires distinct signed sessions")
 race=str(uuid.uuid4())
 with ThreadPoolExecutor(max_workers=2) as pool:
  f1=pool.submit(success,api,key,a,create,note_args(ENROLL[0],race))
  f2=pool.submit(success,api,key,second,create,note_args(ENROLL[0],race))
  results=[f1.result(),f2.result()]
 check(len({x.get("noteId") for x in results})==1 and
       {x.get("replay") for x in results}=={True,False},
       "Signed simultaneous duplicate request not serialized/idempotent")
 # Released-source-shaped negative transitions, all fictional and local:
 # pause Teaching, retire Ledger, unpublish edition and revoke current bindings.
 db(f"UPDATE atlas.capability_activations SET state='paused' WHERE id='{ACTIVATION}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Paused source-governed Teaching reader denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Paused source-governed Teaching writer denied")
 db(f"UPDATE atlas.capability_activations SET state='active' WHERE id='{ACTIVATION}';")
 db(f"UPDATE atlas.ledgers SET status='retired' WHERE id='{LEDGER}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Retired source Ledger reader denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Retired source Ledger writer denied")
 db(f"UPDATE atlas.ledgers SET status='active' WHERE id='{LEDGER}';")
 db(f"UPDATE atlas.teaching_course_versions SET published_at=NULL WHERE id='{VERSION}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Unpublished Course Version reader denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Unpublished Course Version writer denied")
 db(f"UPDATE atlas.teaching_course_versions SET published_at=now() WHERE id='{VERSION}';")
 db(f"UPDATE atlas.person_auth_credentials SET status='retired',retired_at=now() WHERE auth_user_id='{users[0][0]}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Retired current-Person credential reader denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Retired current-Person credential writer denied")
 db(f"UPDATE atlas.person_auth_credentials SET status='active',retired_at=NULL WHERE auth_user_id='{users[0][0]}';")
 db(f"UPDATE reality.auth_person_bindings SET binding_state='retired',retired_at=now() WHERE auth_user_id='{users[0][0]}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Retired canonical Reality binding reader denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Retired canonical Reality binding writer denied")
 db(f"UPDATE reality.auth_person_bindings SET binding_state='active',retired_at=NULL WHERE auth_user_id='{users[0][0]}';")
 db(f"UPDATE atlas.teaching_enrollments SET state='withdrawn',withdrawn_at=now() WHERE id='{ENROLL[0]}';")
 deny(api,key,a,read,read_args(ENROLL[0]),"Withdrawn learner read denied")
 deny(api,key,second,create,note_args(ENROLL[0]),"Withdrawn learner write denied")
 db(f"UPDATE atlas.teaching_enrollments SET state='active',withdrawn_at=NULL WHERE id='{ENROLL[0]}';")
 db(f"DELETE FROM auth.sessions WHERE id='{signed[0][1]['session_id']}'::uuid")
 deny(api,key,a,read,read_args(ENROLL[0]),"Revoked genuine OAuth session denied")
 check(db(f"SELECT count(*) FROM titus.learner_private_course_note_events_v1 WHERE enrollment_id='{ENROLL[0]}'")=="2",
       "Signed denials altered originals")
 Path(ARGS.output).write_text(
  "PASS genuine LOCAL OAuth PKCE three-Person signed source and REST matrix; "
  "private self create/read, other Person and unauthenticated denial, OAuth client guard, "
  "two-session concurrent replay, withdrawn Enrollment and revoked signed session. "
  "DISPOSABLE local source only; no production clone/real user.\n",encoding="utf8")
 print("PASS all local GoTrue OAuth/REST assertions (not production-shaped custody)")
if __name__=="__main__":
 main()
