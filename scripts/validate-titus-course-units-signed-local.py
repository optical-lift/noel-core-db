#!/usr/bin/env python3
"""Genuine GoTrue-signed bearer / PostgREST proof, on a disposable LOCAL DB only.

All Auth accounts and Unit text are synthetic. This is NOT acceptance by the
real customer or an independently consenting second human. Never run remotely.
No tokens, passwords, Course bodies or personal identifiers enter job output.
"""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import json
import re
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request

READ="titus_customer_material_read_self_api_v1"
SAVE="titus_customer_material_save_self_api_v1"
UUID_RE=re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",re.I)
LOOPBACK={"127.0.0.1","localhost"}
OPENER=urllib.request.build_opener(urllib.request.ProxyHandler({}))

def check(ok, reason):
    if not ok: raise AssertionError(reason)

def sql(db, query):
    run=subprocess.run(["psql",db,"-X","-A","-t","-v","ON_ERROR_STOP=1","-c",query],
        capture_output=True,text=True,check=True)
    return run.stdout.strip()

def local_credentials():
    run=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=True)
    env={}
    for line in run.stdout.splitlines():
        if "=" in line:
            name,value=line.split("=",1)
            env[name.strip()]=value.strip().strip('"')
    api=env.get("API_URL","").rstrip("/")
    key=env.get("ANON_KEY") or env.get("SUPABASE_ANON_KEY")
    service=env.get("SERVICE_ROLE_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY")
    parsed=urllib.parse.urlparse(api)
    check(parsed.scheme=="http" and parsed.hostname in LOOPBACK and
          parsed.port is not None and parsed.username is None and
          parsed.password is None and parsed.path=="","Refuse nonlocal Auth API")
    check(bool(key and service),"Missing disposable local Auth keys")
    return api,key,service

def call(api,key,path,body,token=None):
    headers={"apikey":key,"Content-Type":"application/json","Accept":"application/json"}
    if token is not None:headers["Authorization"]="Bearer "+token
    req=urllib.request.Request(api+path,data=json.dumps(body).encode("utf-8"),
                               headers=headers,method="POST")
    try:
        with OPENER.open(req,timeout=25) as resp:
            raw=resp.read().decode("utf-8")
            return resp.status,json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw=exc.read().decode("utf-8")
        try: return exc.code,json.loads(raw) if raw else None
        except json.JSONDecodeError: return exc.code,None

def payload(token):
    try:
        segment=token.split(".")[1]
        return json.loads(base64.urlsafe_b64decode(segment+"="*(-len(segment)%4)))
    except Exception as e:raise AssertionError("Malformed locally signed Auth JWT") from e

def positive(api,key,token,name,data,label):
    status,result=call(api,key,"/rest/v1/rpc/"+name,data,token)
    check(status==200 and isinstance(result,dict),f"{label}: signed success failed HTTP {status}")
    return result

def negative(api,key,token,name,data,label,codes=("42501",)):
    status,result=call(api,key,"/rest/v1/rpc/"+name,data,token)
    check(status in (401,403,409,500) and isinstance(result,dict),
          f"{label}: expected source denial, observed HTTP {status}")
    check(result.get("code") in codes,
          f"{label}: wrong denial type {result.get('code')}; never accept missing RPC")
    print("PASS",label)

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url",required=True)
    p.add_argument("--output",required=True)
    args=p.parse_args()
    check(re.fullmatch(r"postgres(ql)?://postgres:postgres@127[.]0[.]0[.]1:[0-9]{2,5}/postgres",
                       args.db_url) is not None,"Refuse nonlocal or privileged production database")
    # Docker port forwarding uses a localhost client address even if the
    # server reports its internal bridge IP. The exact db-url regex above,
    # not inet_server_addr(), is the remote-destination prevention boundary.
    check(sql(args.db_url,"SELECT current_database()")=="postgres",
          "Unexpected disposable local database")
    api,key,service=local_credentials()
    suffix=secrets.token_hex(5)
    password=secrets.token_urlsafe(26)
    users={}
    for role in ("owner_a","owner_b","outsider"):
        address=f"titus-signed-{role}-{suffix}@example.invalid"
        status,result=call(api,service,"/auth/v1/admin/users",
            {"email":address,"password":password,"email_confirm":True},service)
        check(status in (200,201) and isinstance(result,dict) and
              UUID_RE.fullmatch(str(result.get("id",""))) is not None,
              f"{role}: local GoTrue test-account creation failed: HTTP {status}")
        uid=result["id"]
        status,login=call(api,key,"/auth/v1/token?grant_type=password",
                          {"email":address,"password":password})
        check(status==200 and isinstance(login,dict) and
              isinstance(login.get("access_token"),str),
              f"{role}: genuine GoTrue login failed: HTTP {status}")
        token=login["access_token"];claims=payload(token)
        sid=claims.get("session_id")
        check(claims.get("role")=="authenticated" and claims.get("sub")==uid and
              isinstance(sid,str) and UUID_RE.fullmatch(sid) is not None,
              f"{role}: invalid signed session claims")
        check(sql(args.db_url,f"SELECT count(*) FROM auth.sessions WHERE id='{sid}'::uuid "
                    f"AND user_id='{uid}'::uuid")=="1",
              f"{role}: GoTrue session not persisted in local Auth")
        users[role]={"id":uid,"token":token,"sid":sid,"email":address}
    print("PASS three independent, genuinely signed local GoTrue sessions")


    a=users["owner_a"];b=users["owner_b"];outsider=users["outsider"]
    for item in (a,b):
        receipt="fictional-units-"+secrets.token_hex(12)
        sql(args.db_url,"INSERT INTO titus.customer_workspace_entitlements_v1 "
            "(owner_auth_user_id,grant_kind,grant_source_receipt) "
            f"VALUES('{item['id']}'::uuid,'private_pilot','{receipt}')")
    negative(api,key,outsider["token"],"titus_customer_catalog_self_api_v1",{},
             "unentitled signed outsider denied")

    def create_course(actor,label,title):
        catalog=positive(api,key,actor["token"],"titus_customer_start_workspace_self_api_v1",
            {"p_title":"Disposable Course Studio"},label+" signed workspace")
        created=positive(api,key,actor["token"],"titus_customer_create_course_self_api_v1",
            {"p_request_id":secrets_uuid(),"p_title":title},label+" signed original Course")
        courses=created.get("courses",[])
        candidate=[item for item in courses if item.get("title")==title]
        check(len(candidate)==1 and UUID_RE.fullmatch(str(candidate[0].get("courseId",""))),
              label+": expected exact newly owned Course")
        return candidate[0]["courseId"]

    a1=create_course(a,"A1","Fictional Lab A1")
    a2=create_course(a,"A2","Fictional Lab A2")
    b1=create_course(b,"B1","Fictional Lab B")
    def outline(token,course,label):
        r=positive(api,key,token,"titus_customer_outline_read_self_api_v1",
                   {"p_course_id":course},label)
        check(r.get("courseId")==course and isinstance(r.get("units"),list),
              label+": wrong Course outline")
        return r
    check(outline(a["token"],a1,"A1 blank")["units"]==[], "Do not seed A1")
    check(outline(a["token"],a2,"A2 blank")["units"]==[], "Do not seed A2")
    check(outline(b["token"],b1,"B1 blank")["units"]==[], "Do not seed B1")
    negative(api,key,b["token"],"titus_customer_outline_read_self_api_v1",
             {"p_course_id":a1},"other entitled owner A outline denied")
    negative(api,key,outsider["token"],"titus_customer_outline_read_self_api_v1",
             {"p_course_id":a1},"unentitled A outline denied")
    negative(api,key,None,"titus_customer_outline_read_self_api_v1",
             {"p_course_id":a1},"anonymous outline denied")
    print("PASS real signed empty outlines and independent owned Courses")

    create_name="titus_customer_unit_create_self_api_v1"
    move_name="titus_customer_unit_move_self_api_v1"
    read_name="titus_customer_unit_read_self_api_v1"
    save_name="titus_customer_unit_save_self_api_v1"
    req1={"p_course_id":a1,"p_request_id":secrets_uuid(),
          "p_kind":"lesson","p_title":"A1 genuine signed local Class"}
    result=positive(api,key,a["token"],create_name,req1,"A1 class create")
    check(len(result["units"])==1,"Class count")
    unit=result["units"][0]["unitId"]
    req2={"p_course_id":a1,"p_request_id":secrets_uuid(),
          "p_kind":"assignment","p_title":"A1 fictional Homework"}
    result=positive(api,key,a["token"],create_name,req2,"A1 homework create")
    check(len(result["units"])==2,"Homework count")
    homework=result["units"][1]["unitId"]
    check(result["units"][0]["kind"]=="lesson" and result["units"][1]["kind"]=="assignment",
          "Unit types and order not correctly persisted")
    repeated=positive(api,key,a["token"],create_name,req1,"A1 class create same-receipt retry")
    check(len(repeated["units"])==2,"Create retry duplicated class")
    negative(api,key,a["token"],create_name,{**req1,"p_title":"Changed original"},
             "changed class-create replay denied",("23505",))
    moved=positive(api,key,a["token"],move_name,
      {"p_course_id":a1,"p_unit_id":homework,"p_direction":"up"},
      "signed reorder homework above Class")
    check([x["unitId"] for x in moved["units"]]==[homework,unit],"Reorder did not persist")
    negative(api,key,a["token"],move_name,
      {"p_course_id":a2,"p_unit_id":unit,"p_direction":"up"},
      "same-owner wrong-Course reorder denied")
    check([x["unitId"] for x in outline(a["token"],a1,"A1 after denied cross-Course move")["units"]]==
          [homework,unit],"Wrong Course request mutated A1 order")
    check(outline(a["token"],a2,"A2 still blank")["units"]==[],"Wrong-Course request mutated A2")
    for label,token in (("foreign-entitled",b["token"]),("unentitled",outsider["token"])):
        negative(api,key,token,read_name,{"p_unit_id":unit},label+" class read denied")
        negative(api,key,token,save_name,
          {"p_unit_id":unit,"p_request_id":secrets_uuid(),
           "p_expected_revision":0,"p_text":"Unauthorized"},
          label+" class save denied")
        negative(api,key,token,move_name,
          {"p_course_id":a1,"p_unit_id":unit,"p_direction":"up"},
          label+" class reorder denied")
    negative(api,key,None,read_name,{"p_unit_id":unit},"anonymous class read denied")
    print("PASS owner class+homework create/order, idempotency, cross-Course and foreign denials")

    blank=positive(api,key,a["token"],read_name,{"p_unit_id":unit},"blank A1 class")
    check(blank.get("material") is None,"Source silently seeded a class")
    attempt={"p_unit_id":unit,"p_request_id":secrets_uuid(),
             "p_expected_revision":0,"p_text":"Only synthetic private Class A"}
    wrote=positive(api,key,a["token"],save_name,attempt,"first original signed class save")
    check(wrote.get("material",{}).get("text")==attempt["p_text"] and
          wrote["material"].get("revisionNumber")==1,"Original class save missing")
    retry=positive(api,key,a["token"],save_name,attempt,"same exact class-save retry")
    check(retry["material"]["revisionNumber"]==1,"Retry invented revision")
    negative(api,key,a["token"],save_name,{**attempt,"p_text":"Modified replay"},
             "same-receipt changed class denial",("23505",))
    negative(api,key,a["token"],save_name,{**attempt,"p_request_id":secrets_uuid(),
             "p_text":"Stale writer"},"stale original revision denied",("40001",))
    homework_req={"p_unit_id":homework,"p_request_id":secrets_uuid(),
                  "p_expected_revision":0,"p_text":"Synthetic independent homework"}
    saved_homework=positive(api,key,a["token"],save_name,homework_req,"signed homework save")
    check(saved_homework["material"]["revisionNumber"]==1,"Homework save missing")
    check(positive(api,key,a["token"],read_name,{"p_unit_id":unit},"class reopen")
          ["material"]["text"]==attempt["p_text"],"Homework write overwrote class")
    course_original=positive(api,key,a["token"],"titus_customer_material_read_self_api_v1",
                             {"p_course_id":a1},"original Course manuscript read")
    check(course_original.get("material") is None,
          "Unit write seeded/overwrote original founding manuscript")
    print("PASS two distinct signed unit originals and unchanged Course-level manuscript")

    status,login2=call(api,key,"/auth/v1/token?grant_type=password",
                       {"email":a["email"],"password":password})
    check(status==200 and isinstance(login2,dict) and
          isinstance(login2.get("access_token"),str),"Second actual signed owner login unavailable")
    token2=login2["access_token"];claims2=payload(token2)
    check(claims2.get("sub")==a["id"] and claims2.get("session_id")!=a["sid"],
          "No independent signed owner session")
    check(positive(api,key,token2,read_name,{"p_unit_id":unit},
          "second signed session class reopen")["material"]["revisionNumber"]==1,
          "Second session cannot read exact previous original")
    raced=[
      {"p_unit_id":unit,"p_request_id":secrets_uuid(),
       "p_expected_revision":1,"p_text":"Parallel signed class original A"},
      {"p_unit_id":unit,"p_request_id":secrets_uuid(),
       "p_expected_revision":1,"p_text":"Parallel signed class original B"},
    ]
    with ThreadPoolExecutor(max_workers=2) as executor:
        f1=executor.submit(call,api,key,"/rest/v1/rpc/"+save_name,raced[0],a["token"])
        f2=executor.submit(call,api,key,"/rest/v1/rpc/"+save_name,raced[1],token2)
        responses=[f1.result(),f2.result()]
    winners=[i for i,(status,v) in enumerate(responses) if status==200]
    conflicts=[v for status,v in responses if status in (409,500) and
              isinstance(v,dict) and v.get("code")=="40001"]
    check(len(winners)==1 and len(conflicts)==1,
          "Two genuine signed simultaneous unit saves must produce exactly one winner")
    readback=positive(api,key,a["token"],read_name,{"p_unit_id":unit},"concurrent saved reopen")
    check(readback["material"]["revisionNumber"]==2 and
          readback["material"]["text"]==raced[winners[0]]["p_text"],
          "Concurrent Class readback not latest exact winner")
    check(sql(args.db_url,"SELECT count(*) FROM titus.customer_course_unit_revisions_v1 "
                          f"WHERE unit_id='{unit}'::uuid")=="2",
          "Lost-update protection failed: duplicate revision")
    print("PASS two real signed owner sessions, exactly one concurrent class writer")

    # A separately entitled owner's own Course and Unit must be accessible
    # before their purely local trial entitlement is withdrawn.
    req_b={"p_course_id":b1,"p_request_id":secrets_uuid(),
           "p_kind":"lesson","p_title":"B own original local Class"}
    b_units=positive(api,key,b["token"],create_name,req_b,"B own class create")
    bunit=b_units["units"][0]["unitId"]
    b_save={"p_unit_id":bunit,"p_request_id":secrets_uuid(),
            "p_expected_revision":0,"p_text":"B personal fictional lesson"}
    check(positive(api,key,b["token"],save_name,b_save,"B own class save")
          ["material"]["revisionNumber"]==1,"B own positive control failed")
    sql(args.db_url,f"UPDATE titus.customer_workspace_entitlements_v1 SET state='revoked' "
                    f"WHERE owner_auth_user_id='{b['id']}'::uuid")
    negative(api,key,b["token"],read_name,{"p_unit_id":bunit},
             "B own class read denied after local revocation")
    negative(api,key,b["token"],save_name,
      {**b_save,"p_request_id":secrets_uuid(),"p_expected_revision":1,
       "p_text":"Denied after local entitlement withdrawal"},
      "B own class save denied after revocation")
    negative(api,key,b["token"],"titus_customer_outline_read_self_api_v1",
      {"p_course_id":b1},"B own outline denied after revocation")
    check(positive(api,key,a["token"],read_name,{"p_unit_id":unit},
          "unrelated A signed access still active")["material"]["revisionNumber"]==2,
          "B local revocation affected A")
    print("PASS genuine local signed entitlement withdrawal; no real grant touched")

    sid2=claims2.get("session_id")
    check(isinstance(sid2,str) and UUID_RE.fullmatch(sid2),
          "Second GoTrue session ID missing")
    sql(args.db_url,"UPDATE auth.sessions SET not_after=now()-interval '1 minute' "
      f"WHERE id='{sid2}'::uuid AND user_id='{a['id']}'::uuid")
    negative(api,key,token2,read_name,{"p_unit_id":unit},
             "expired second owner session read denied")
    negative(api,key,token2,save_name,
      {"p_unit_id":unit,"p_request_id":secrets_uuid(),
       "p_expected_revision":2,"p_text":"Expired local session write"},
      "expired second owner session write denied")
    check(positive(api,key,a["token"],read_name,{"p_unit_id":unit},
          "original still-active signed owner session")["material"]["revisionNumber"]==2,
          "Separate expired session broke legitimate original")
    check(sql(args.db_url,"SELECT count(*) FROM titus.customer_course_unit_revisions_v1")=="4",
          "Foreign/expired/replayed requests wrote private history")
    with open(args.output,"w",encoding="utf-8") as fp:
        fp.write(json.dumps({"scope":"fully_disposable_local_auth_and_rest",
         "goTrueSessions":4,"ownedCourses":3,"sourceOnly":True,
         "signedUnitContracts":"PASS","realHumanAcceptance":False,
         "productionWrites":False},sort_keys=True)+"\n")
    print("PASS genuine local GoTrue signed Course Unit matrix, never production")

def secrets_uuid():
    import uuid
    return str(uuid.uuid4())

if __name__=="__main__":main()
