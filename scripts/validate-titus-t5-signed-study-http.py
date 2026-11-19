#!/usr/bin/env python3
"""Fictional, independent GoTrue/PostgREST T5 proof on a schema-only local clone.
Exact held source must be installed on the job-owned disposable DB first.
No real account, course, data dump, public release, or external mailbox.
"""
import argparse
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
    for _ in range(20):
        st,_=auth.rpc(api,key,"shared_teaching_private_study_delivery_self_api_v1",{"p_course_id":uid()},tokens["author"])
        if st==403: break
        time.sleep(.5)
    else: raise AssertionError("held REST source unavailable")
    check(rpc("author","titus_authoring_access_self_api_v1",{})["canUseTitus"] is True,"signed owner author access")
    check(rpc("learner","titus_authoring_access_self_api_v1",{})["canUseTitus"] is False,"learner not author")
    check(course("author","catalog")["courses"]==[],"empty first owner catalog")
    create={"p_request_id":uid(),"p_title":"Fictional teaching study"}
    cid=course("author","create",**create)["courseId"]
    check(course("author","create",**create)["courseId"]==cid,"same course retry")
    course("author","material_save",p_course_id=cid,p_request_id=uid(),p_expected_revision=0,p_text="Fictional complete manuscript.")
    root=course("author","unit_create",p_course_id=cid,p_request_id=uid(),p_kind="lesson",p_title="Fictional class")["units"][0]["unitId"]
    units=course("author","unit_create",p_course_id=cid,p_request_id=uid(),p_kind="assignment",p_title="Fictional question")["units"]
    child=next(x["unitId"] for x in units if x["unitId"]!=root)
    activity=uid()
    question="What did you observe?"
    body="## Question {#titus-activity:"+activity+"}\n\n"+question
    course("author","unit_save",p_unit_id=root,p_request_id=uid(),p_expected_revision=0,p_text="Fictional class.")
    rev=course("author","unit_save",p_unit_id=child,p_request_id=uid(),p_expected_revision=0,p_text=body)["material"]["revisionId"]
    course("author","composition_save",p_course_id=cid,p_request_id=uid(),p_expected_revision=0,p_members=[{"unitId":child,"classUnitId":root,"depth":"foundational"}])
    prep={"p_course_id":cid,"p_request_id":uid(),"p_title":"Fictional private edition"}
    edition=study("author","prepare_edition",**prep)
    check(study("author","prepare_edition",**prep)["snapshotId"]==edition["snapshotId"],"same edition retry")
    inv=study("author","invite",p_course_id=cid,p_learner_person_entity_id=person(102),p_request_id=uid(),p_expires_at=None)["invitationId"]
    ii={"p_invitation_id":inv}
    unit={"p_invitation_id":inv,"p_unit_id":child}
    issue={**unit,"p_request_id":uid(),"p_decision":"allow","p_course_version_id":edition["courseVersionId"]}
    study("author","unit_decide",403,**issue)
    study("learner","sealed_unit_read",403,**unit)
    study("outsider","offer_read",403,**ii)
    consent={**ii,"p_request_id":uid(),"p_decision":"accept"}
    study("author","respond",403,**consent)
    study("learner","respond",**consent)
    check(study("learner","respond",**consent)["alreadyExists"] is True,"consent retry")
    check(study("learner","index",**ii)["units"]==[],"acceptance alone discloses nothing")
    study("learner","sealed_unit_read",403,**unit)
    study("author","unit_decide",**issue)
    check(study("author","unit_decide",**issue)["alreadyExists"] is True,"issue retry")
    sealed=study("learner","sealed_unit_read",**unit)
    check(sealed["snapshotId"]==edition["snapshotId"] and sealed["unit"]["revisionId"]==rev and sealed["unit"]["text"]==body,"exact immutable issued revision")
    study("outsider","sealed_unit_read",403,**unit)
    parent_issue={**issue,"p_unit_id":root,"p_request_id":uid()}
    study("author","unit_decide",**parent_issue)
    course("author","composition_save",p_course_id=cid,p_request_id=uid(),p_expected_revision=1,p_members=[])
    index=study("learner","index",**ii)["units"]
    check(next(x for x in index if x["unitId"]==child)["classUnitId"]==root,"sealed grouping retained")
    withhold={**parent_issue,"p_request_id":uid(),"p_decision":"withhold","p_course_version_id":None}
    study("learner","unit_decide",403,**withhold)
    study("author","unit_decide",**withhold)
    study("learner","sealed_unit_read",403,p_invitation_id=inv,p_unit_id=root)
    index=study("learner","index",**ii)["units"]
    check(len(index)==1 and index[0]["classUnitId"] is None,"withheld parent concealed")
    scope=dict(p_invitation=inv,p_unit=child,p_snapshot=edition["snapshotId"],p_unit_revision=rev,p_activity=activity)
    study("author","answer_read",403,**scope)
    check(study("learner","answer_read",**scope)["revisionNumber"]==0,"private empty answer")
    first={**scope,"p_request":uid(),"p_expected_revision":0,"p_text":"First fictional observation"}
    a1=study("learner","answer_save",**first)
    check(study("learner","answer_save",**first)==a1,"answer retry")
    a2=study("learner","answer_save",**{**first,"p_request":uid(),"p_expected_revision":1,"p_text":"Later private finding"})
    check(answer("author","review_inbox",p_course_id=cid,p_before=None)["items"]==[],"saving not disclosure")
    answer("author","review_target",403,p_answer_revision_id=a1["answerRevisionId"])
    target=answer("learner","review_target",p_answer_revision_id=a1["answerRevisionId"])
    check(target["reviewerPersonId"]==person(101),"exact original author")
    submission=answer("learner","submit",p_answer_revision_id=a1["answerRevisionId"],p_reviewer_person_id=person(101),p_request_id=uid())["submissionId"]
    review=dict(p_submission_id=submission,p_mode="reviewer")
    check(answer("author","submission_read",**review)["text"] is None,"no read before acceptance")
    check(answer("author","question_context",**review)["prompt"] is None,"no prompt before acceptance")
    answer("outsider","submission_read",403,**review)
    event=dict(p_submission_id=submission,p_request_id=uid(),p_action="accept_review",p_feedback=None)
    answer("learner","review_event",403,**event)
    answer("author","review_event",**event)
    check(answer("author","submission_read",**review)["text"]==first["p_text"],"only selected earlier answer disclosed")
    check(answer("author","question_context",**review)["prompt"]==question,"exact original question")
    answer("author","own_history",403,p_answer_revision_id=a2["answerRevisionId"])
    answer("author","review_event",**{**event,"p_request_id":uid(),"p_action":"feedback","p_feedback":"Fictional feedback"})
    own={**review,"p_mode":"learner"}
    check(answer("learner","submission_read",**own)["feedback"]["text"]=="Fictional feedback","learner feedback")
    check(answer("learner","own_history",p_answer_revision_id=a2["answerRevisionId"])["history"][0]["submissionId"]==submission,"own selected prior history")
    answer("learner","review_event",**{**event,"p_request_id":uid(),"p_action":"withdraw"})
    answer("author","submission_read",403,**review)
    check(study("learner","answer_read",**scope)["text"]=="Later private finding","private revision unchanged")
    study("learner","withdraw",**ii,p_request_id=uid())
    study("learner","sealed_unit_read",403,**unit)
    study("learner","answer_read",403,**scope)
    check(sql(f"SELECT count(*) FROM atlas.teaching_course_private_study_answer_revisions WHERE invitation_id='{inv}'")=="2","originals preserved")
    check(sql("SELECT count(*) FROM atlas.teaching_courses")=="1","same original only")
    check(sql("SELECT count(*) FROM atlas.teaching_enrollments")=="0","no institutional enrollment created")
    Path(a.output).write_text("PASS T5 independent local signed study journey\n")
    print("PASS T5 independent local signed study journey")
if __name__=="__main__":
    main()
