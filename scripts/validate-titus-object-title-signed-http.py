#!/usr/bin/env python3
"""Fictional independent signed title proof on a schema-only local clone.
Exact held source must be installed on the job-owned disposable DB first.
No real account, course, data dump, public release, or external mailbox.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import re
import time
import uuid

spec = importlib.util.spec_from_file_location("local_auth", Path(__file__).with_name("validate-atlas-c1-signed-http.py"))
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
def check(v, m):
    if not v:
        raise AssertionError(m)
def uid():
    return str(uuid.uuid4())
def person(n):
    return f"f5a00000-0000-4000-8000-{n:012d}"
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--db-url", required=True)
    p.add_argument("--output", required=True)
    a=p.parse_args()
    check(re.fullmatch(r"postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url), "disposable loopback DB required")
    check(not any(os.getenv(k) for k in ("NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_DB_URL","SUPABASE_ACCESS_TOKEN","SUPABASE_SERVICE_ROLE_KEY","SUPABASE_SECRET_KEY")), "hosted credentials forbidden")
    sql=lambda q: auth.sql(a.db_url,q)
    check(sql("SELECT current_setting('server_version_num')::int/10000")=="17","PG17 required")
    check(sql("SELECT (NOT EXISTS(SELECT 1 FROM auth.users) AND NOT EXISTS(SELECT 1 FROM atlas.teaching_courses) AND NOT EXISTS(SELECT 1 FROM atlas.teaching_course_private_study_invitations))")=="t","schema-only empty clone required")
    # Same real schema columns as existing protected canonical Person fixtures.
    # Fake names/credentials are confined to this job. No JWT claim injection.
    for name,n in (("t5-author",1),("t5-learner",2),("t5-outsider",3)):
        user,entity=person(n),person(n+100)
        email=f"atlas-c1-{name}@example.invalid"
        sql(f"""
          INSERT INTO auth.users(id,aud,role,created_at,updated_at,is_anonymous,instance_id,email,
          encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change,email_change_token_new,
          email_change_token_current,phone_change,phone_change_token,reauthentication_token,raw_app_meta_data,raw_user_meta_data)
          VALUES('{user}','authenticated','authenticated',now(),now(),false,'00000000-0000-0000-0000-000000000000','{email}',
          extensions.crypt('{auth.PASSWORD}',extensions.gen_salt('bf')),now(),'','','','','','','','','{{"provider":"email","providers":["email"]}}','{{}}');
          INSERT INTO auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at)
          VALUES(gen_random_uuid(),'{email}','{user}',jsonb_build_object('sub','{user}','email','{email}'),'email',now(),now());
          INSERT INTO reality.entities(id,stable_key,entity_kind,display_name,identity_state)
          VALUES('{entity}','{name}','person','Fictional {name}','canonical');
          INSERT INTO reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis)
          VALUES('{user}','{entity}','active','{{"cloneFixture":true}}');
          INSERT INTO atlas.people(id,display_name,status) VALUES('{entity}','Fictional {name}','active');
          INSERT INTO atlas.person_auth_credentials(person_id,credential_kind,auth_user_id,status,provenance)
          VALUES('{entity}','supabase_auth_user','{user}','active','{{"cloneFixture":true}}');
          INSERT INTO atlas.principals(id,user_id,person_id,stable_key,name,status)
          VALUES('{person(n+200)}','{user}','{entity}','{name}-principal','Fictional {name}','active');
        """)
    # Only disposable fixture grants; never a production issuer.
    for n in (1,2):
        sql(f"""INSERT INTO titus.course_authoring_access_grants(person_entity_id,grant_source_auth_user_id,
           grant_kind,grant_source_receipt,state,granted_at)
           VALUES('{person(n+100)}','{person(1)}','private_pilot','fictional-title-proof-{n}','active',now())""")
    # Explicit synthetic owner responsibility, not new production standing.
    sql(f"""INSERT INTO reality.responsibility_relations(carrier_person_entity_id,responsibility_key,title,relation_state,
        jurisdiction_kind,jurisdiction_domain,permitted_operations,establishment_kind,establishment_basis)
        VALUES('{person(101)}','titus_private_pilot_issuance','Fictional owner','active','domain','titus',
        ARRAY['author_course_as_owner'],'clone_validation_fixture','{{"cloneFixture":true}}');
        NOTIFY pgrst,'reload schema';""")
    api,key=auth.local_status()
    tokens={}
    for role,n in (("author",1),("learner",2),("outsider",3)):
        token,claims=auth.sign_in(api,key,"t5-"+role)
        check(claims["sub"]==person(n),"signed user mismatch")
        session=str(uuid.UUID(claims["session_id"]))
        check(sql(f"SELECT count(*) FROM auth.sessions WHERE id='{session}' AND user_id='{person(n)}'")=="1","persisted separate session required")
        tokens[role]=token
    def rpc(role,name,params,expected=200):
        status,out=auth.rpc(api,key,name,params,tokens.get(role))
        check(status==expected and isinstance(out,dict),f"{name}: expected HTTP {expected}, got {status}")
        if expected==403 and role is not None:
            check(out.get("code")=="42501",f"{name}: source denial required")
        return out
    def course(role,name,**p):
        return rpc(role,"shared_teaching_course_"+name+"_self_api_v1",p)
    def study(role,name,expected=200,**p):
        return rpc(role,"shared_teaching_private_study_"+name+"_self_api_v1",p,expected)
    def answer(role,name,expected=200,**p):
        return rpc(role,"shared_teaching_private_answer_"+name+"_self_api_v1",p,expected)

    def title(role,action,p,expected=200):
        status,out=auth.rpc(api,key,"shared_teaching_object_title_"+action+"_self_api_v1",p,tokens.get(role))
        check(status==expected and isinstance(out,dict),"title "+action+": expected HTTP "+str(expected)+", got "+str(status))
        return out
    def denied(role,action,p,code):
        status,out=auth.rpc(api,key,"shared_teaching_object_title_"+action+"_self_api_v1",p,tokens.get(role))
        check(status>=400 and isinstance(out,dict) and out.get("code")==code,"expected exact title source denial "+code)
    for _ in range(20):
        st,_=auth.rpc(api,key,"shared_teaching_object_title_read_self_api_v1",{"p_course_id":uid(),"p_unit_id":None},tokens["author"])
        if st==403: break
        time.sleep(.5)
    else: raise AssertionError("held title REST source unavailable")
    check(rpc("author","titus_authoring_access_self_api_v1",{})["canUseTitus"] is True,"first author access")
    check(rpc("learner","titus_authoring_access_self_api_v1",{})["canUseTitus"] is True,"second author access")
    check(rpc("outsider","titus_authoring_access_self_api_v1",{})["canUseTitus"] is False,"outsider no grant")
    create={"p_request_id":uid(),"p_title":"Fictional original course"}
    cid=course("author","create",**create)["courseId"]
    other=course("learner","create",**create)["courseId"]
    check(cid!=other,"independent originals")
    root_create=dict(p_course_id=cid,p_request_id=uid(),p_kind="lesson",p_title="Original lesson")
    root=course("author","unit_create",**root_create)["units"][0]["unitId"]
    other_unit=course("learner","unit_create",p_course_id=other,p_request_id=uid(),p_kind="lesson",p_title="Other lesson")["units"][0]["unitId"]
    body="## Opening\n\nFictional original text."
    rev=course("author","unit_save",p_unit_id=root,p_request_id=uid(),p_expected_revision=0,p_text=body)["material"]
    course("author","material_save",p_course_id=cid,p_request_id=uid(),p_expected_revision=0,p_text="Fictional complete manuscript.")
    edition=study("author","prepare_edition",p_course_id=cid,p_request_id=uid(),p_title="Original sealed course")
    sealed=course("author","curriculum_snapshot",p_course_version_id=edition["courseVersionId"])
    inv=study("author","invite",p_course_id=cid,p_learner_person_entity_id=person(102),p_request_id=uid(),p_expires_at=None)["invitationId"]
    study("learner","respond",p_invitation_id=inv,p_request_id=uid(),p_decision="accept")
    study("author","unit_decide",p_invitation_id=inv,p_unit_id=root,p_request_id=uid(),p_decision="allow",p_course_version_id=edition["courseVersionId"])
    issued=study("learner","sealed_unit_read",p_invitation_id=inv,p_unit_id=root)
    check(issued["unit"]["text"]==body and issued["unit"]["title"]=="Original lesson","exact issued title and body before rename")
    course_scope=dict(p_course_id=cid,p_unit_id=None)
    unit_scope=dict(p_course_id=cid,p_unit_id=root)
    check(title("author","read",course_scope)["revisionNumber"]==0,"baseline")
    check(title("author","read",unit_scope)["title"]=="Original lesson","baseline unit")
    rename=dict(**course_scope,p_request_id=uid(),p_expected_revision=0,p_expected_title=create["p_title"],p_title="Renamed course")
    unit_rename=dict(**unit_scope,p_request_id=uid(),p_expected_revision=0,p_expected_title="Original lesson",p_title="Renamed lesson")
    denied("learner","save",rename,"42501")
    denied("outsider","read",course_scope,"42501")
    denied("author","read",dict(p_course_id=cid,p_unit_id=other_unit),"42501")
    denied("author","save",dict(unit_rename,p_unit_id=other_unit),"42501")
    denied("author","save",dict(rename,p_title=""),"22023")
    denied("author","save",dict(rename,p_title="x\ny"),"22023")
    first=title("author","save",rename)
    check(first["current"]["title"]=="Renamed course" and first["revisionNumber"]==1,"canonical rename receipt")
    check(title("author","save",rename)==first,"replay exact")
    denied("author","save",dict(rename,p_title="Different title"),"23505")
    denied("author","save",dict(rename,p_request_id=uid(),p_title="Stale title"),"40001")
    second=title("author","save",dict(rename,p_request_id=uid(),p_expected_revision=1,p_expected_title="Renamed course",p_title="Current course"))
    check(second["revisionNumber"]==2,"second rename")
    replay=title("author","save",rename)
    check(replay["revisionId"]==first["revisionId"] and replay["current"]["title"]=="Current course","old receipt plus current read")
    denied("author","save",dict(unit_rename,p_request_id=rename["p_request_id"]),"23505")
    title("author","save",unit_rename)
    check(course("author","create",**create)["courseId"]==cid,"founding creation retry")
    check(course("author","unit_create",**root_create)["units"][0]["unitId"]==root,"founding Unit retry")
    check(course("author","catalog")["courses"][0]["title"]=="Current course","catalog current")
    check(course("author","unit_read",p_unit_id=root)["unit"]["title"]=="Renamed lesson","Unit current")
    check(course("author","unit_read",p_unit_id=root)["material"]==rev,"manuscript exact")
    check(course("author","curriculum_snapshot",p_course_version_id=edition["courseVersionId"])==sealed,"sealed curriculum unchanged")
    after_issue=study("learner","sealed_unit_read",p_invitation_id=inv,p_unit_id=root)
    check(after_issue["unit"]==issued["unit"] and after_issue["snapshotId"]==issued["snapshotId"],"issued Unit remains exact")
    check(sql(f"SELECT count(*) FROM atlas.teaching_object_title_revisions WHERE course_id='{cid}'")=="3","no duplicate revision")
    competing=[dict(rename,p_request_id=uid(),p_expected_revision=2,p_expected_title="Current course",p_title="Concurrent "+str(i)) for i in range(2)]
    def compete(p):
        return auth.rpc(api,key,"shared_teaching_object_title_save_self_api_v1",p,tokens["author"])
    with ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(compete,competing))
    winners=[out for status,out in results if status==200]
    losers=[out for status,out in results if status>=400]
    check(len(winners)==len(losers)==1 and losers[0].get("code")=="40001","one concurrent winner and one stale conflict")
    winning_title=winners[0]["title"]
    check(sql(f"SELECT count(*) FROM atlas.teaching_object_title_revisions WHERE course_id='{cid}'")=="4","one concurrent revision")
    check(course("author","curriculum_snapshot",p_course_version_id=edition["courseVersionId"])==sealed,"concurrent title changes preserve edition")
    check(sql("SELECT (NOT has_table_privilege('authenticated','atlas.teaching_object_title_revisions','INSERT') AND NOT has_function_privilege('anon','public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text)','EXECUTE') AND NOT has_function_privilege('service_role','public.shared_teaching_object_title_save_self_api_v1(uuid,uuid,uuid,integer,text,text)','EXECUTE'))")=="t","private table/RPC ACL")
    sql(f"""INSERT INTO titus.course_authoring_access_status_events(person_entity_id,request_id,next_state,source_evidence_receipt,recorded_by_auth_user_id)
        VALUES('{person(101)}','{uid()}','revoked','fictional-title-end','{person(1)}')""")
    denied("author","save",dict(rename,p_request_id=uid(),p_expected_revision=3,p_expected_title=winning_title,p_title="Revoked edit"),"42501")
    check(title("author","read",course_scope)["title"]==winning_title,"no write on revoked grant")
    check(course("learner","catalog")["courses"][0]["courseId"]==other,"second owner unchanged")
    Path(a.output).write_text("PASS independent local signed title proof\n")
    print("PASS independent local signed title proof")
if __name__=="__main__":
    main()
