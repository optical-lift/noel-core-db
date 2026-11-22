#!/usr/bin/env python3
"""Signed disposable PostgreSQL proof for the pinned SK101 management candidate."""
import argparse, importlib.util, os, re, subprocess, uuid
from pathlib import Path
spec=importlib.util.spec_from_file_location("local_auth",Path(__file__).with_name("validate-atlas-c1-signed-http.py"))
auth=importlib.util.module_from_spec(spec); spec.loader.exec_module(auth)
def uid(): return str(uuid.uuid4())
def person(n): return f"f5b00000-0000-4000-8000-{n:012d}"
def check(v,m):
    if not v: raise AssertionError(m)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--db-url",required=True); ap.add_argument("--output",required=True); a=ap.parse_args()
    check(re.fullmatch(r"postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres",a.db_url),"loopback clone")
    check(not any(os.getenv(k) for k in ("NOEL_CORE_DATABASE_URL","DATABASE_URL","SUPABASE_DB_URL","SUPABASE_SERVICE_ROLE_KEY")),"hosted credential")
    sql=lambda q: auth.sql(a.db_url,q)
    check(sql("select current_setting('server_version_num')::int/10000")=="17","PG17")
    check(sql("select not exists(select 1 from auth.users) and not exists(select 1 from atlas.teaching_courses)")=="t","empty clone")
    owner, outsider, entity, other = person(1),person(2),person(101),person(102)
    for user,ent,label in ((owner,entity,"owner"),(outsider,other,"outsider")):
        email=f"sk101-management-{label}@example.invalid"
        sql(f"""insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous,instance_id,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,phone_change,phone_change_token,reauthentication_token,raw_app_meta_data,raw_user_meta_data)
        values('{user}','authenticated','authenticated',now(),now(),false,'00000000-0000-0000-0000-000000000000','{email}',extensions.crypt('{auth.PASSWORD}',extensions.gen_salt('bf')),now(),'','','','','','','','','','{{"provider":"email","providers":["email"]}}','{{}}');
        insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at) values(gen_random_uuid(),'{email}','{user}',jsonb_build_object('sub','{user}','email','{email}'),'email',now(),now());
        insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values('{ent}','sk101-{label}','person','Synthetic {label}','canonical');
        insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values('{user}','{ent}','active','{{"cloneFixture":true}}');""")
    course=uid(); unit=uid(); unit2=uid(); carrier=uid(); principal=uid(); authz=uid(); cred=uid(); req=uid(); token="A"*43
    sql(f"""insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values('{principal}','{owner}','{entity}','sk101-management','Synthetic owner','active');
    insert into atlas.teaching_courses(id,course_key,name,status,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{course}','synthetic-sk101','Synthetic SK101','active','{entity}','{owner}',now());
    insert into atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{unit}','{course}',gen_random_uuid(),'lesson','Class 1',1024,'{entity}','{owner}',now());
    insert into atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{unit2}','{course}',gen_random_uuid(),'lesson','Class 2',2048,'{entity}','{owner}',now());
    insert into atlas.delegated_agent_carriers(id,stable_key,display_name,carrier_kind,provider_key,status,metadata) values('{carrier}','chatgpt_atlas_private','Synthetic carrier','ai_agent','openai','active',jsonb_build_object('pluginId','plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1','ownerPrincipalId','{principal}'));
    insert into atlas.delegated_agent_authorizations(id,carrier_id,principal_id,authorization_state,max_execution_class,allowed_command_keys,denied_command_keys,scope,confirmation_policy,purpose,basis,begins_at,ends_at,created_by_user_id) values('{authz}','{carrier}','{principal}','active','commit',array['teaching.course.management.read','teaching.course.management.write'],array[]::text[],jsonb_build_object('targetKinds',jsonb_build_array('teaching_course'),'targetIds',jsonb_build_array('{course}')),jsonb_build_object('forceAllCommits',false),'Synthetic management grant','{{"establishedBy":"cloneFixture","userId":"{owner}"}}',now(),null,'{owner}');
    insert into atlas.delegated_agent_credentials(id,authorization_id,token_hash,credential_state,begins_at,expires_at,metadata) values('{cred}','{authz}',lower(encode(digest('{token}','sha256'),'hex')),'active',now(),null,'{{"privateCarrierCredentialV1":"true"}}');""")
    api,anon=auth.local_status(); ot,_=auth.sign_in(api,anon,"sk101-management-owner"); xt,_=auth.sign_in(api,anon,"sk101-management-outsider")
    service=subprocess.run(["supabase","status","-o","env"],capture_output=True,text=True,check=True).stdout
    env=dict(x.split("=",1) for x in service.splitlines() if "=" in x); key=(env.get("SERVICE_ROLE_KEY") or env.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip('"'); check(key,"local service key")
    h=__import__("hashlib").sha256(token.encode()).hexdigest()
    def rpc(name,p,role="owner",expected=200,audience="service"):
        if isinstance(role,int):
            expected,role=role,"owner"
        bearer=key if audience=="service" else (ot if role=="owner" else xt)
        status,val=auth.rpc(api,key,name,p,bearer); check(status==expected,f"{name} status {status}: {val}"); return val
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit},"owner",403,"person")
    title=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit}) 
    check(title["title"]=="Class 1","unit title read")
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit},"outsider",403,"person")
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":uid(),"p_operation":"unit_title_read","p_unit":unit},"owner",403,"service")
    check(rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":"b"*64,"p_course":course,"p_operation":"unit_title_read","p_unit":unit},"owner",403,"service") is not None,"bad credential denied")
    write={"p_token_hash":h,"p_course":course,"p_operation":"unit_title_save","p_unit":unit,"p_request":req,"p_expected_revision":0,"p_payload":{"expectedTitle":"Class 1","title":"Class 01 — Reality Is Readable"}}
    other_before=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit2})["title"]
    receipt=rpc("shared_delegated_course_management_write_service_v1",write); replay=rpc("shared_delegated_course_management_write_service_v1",write); check(replay==receipt,"title replay")
    changed={**write,"p_payload":{"expectedTitle":"Class 1","title":"Changed replay"}}; rpc("shared_delegated_course_management_write_service_v1",changed,"owner",409,"service")
    stale={**write,"p_request":uid()}; rpc("shared_delegated_course_management_write_service_v1",stale,"owner",409,"service")
    check(rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit})["title"]=="Class 01 — Reality Is Readable","title readback")
    check(rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit2})["title"]==other_before,"unrelated Unit unchanged")
    rpc("shared_delegated_course_management_write_service_v1",write,"outsider",403,"person")
    sql(f"update atlas.delegated_agent_authorizations set authorization_state='revoked' where id='{authz}'")
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit},"owner",403,"person")
    check(sql(f"select count(*) from atlas.teaching_course_versions where course_id='{course}'")=="0","unpublished")
    Path(a.output).write_text("PASS signed SK101 management clone\n")
    print("PASS signed SK101 management clone")
if __name__=="__main__": main()
