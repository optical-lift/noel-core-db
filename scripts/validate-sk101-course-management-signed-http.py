#!/usr/bin/env python3
"""Signed disposable PostgreSQL proof for the pinned SK101 management candidate."""
import argparse, importlib.util, os, re, subprocess, sys, uuid
from concurrent.futures import ThreadPoolExecutor
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
    def sql(q):
        try:
            return auth.sql(a.db_url,q)
        except subprocess.CalledProcessError as exc:
            print(exc.stderr or exc.stdout or "synthetic fixture SQL failed", file=sys.stderr)
            raise
    check(sql("select current_setting('server_version_num')::int/10000")=="17","PG17")
    check(sql("select not exists(select 1 from auth.users) and not exists(select 1 from atlas.teaching_courses)")=="t","empty clone")
    owner, outsider, entity, other = person(1),person(2),person(101),person(102)
    for user,ent,label in ((owner,entity,"owner"),(outsider,other,"outsider")):
        email=f"atlas-c1-sk101-management-{label}@example.invalid"
        sql(f"""insert into auth.users(id,aud,role,created_at,updated_at,is_anonymous,instance_id,email,encrypted_password,email_confirmed_at,confirmation_token,recovery_token,email_change,email_change_token_new,email_change_token_current,phone_change,phone_change_token,reauthentication_token,raw_app_meta_data,raw_user_meta_data)
        values('{user}','authenticated','authenticated',now(),now(),false,'00000000-0000-0000-0000-000000000000','{email}',extensions.crypt('{auth.PASSWORD}',extensions.gen_salt('bf')),now(),'','','','','','','','','{{"provider":"email","providers":["email"]}}','{{}}');
        insert into auth.identities(id,provider_id,user_id,identity_data,provider,created_at,updated_at) values(gen_random_uuid(),'{email}','{user}',jsonb_build_object('sub','{user}','email','{email}'),'email',now(),now());
        insert into reality.entities(id,stable_key,entity_kind,display_name,identity_state) values('{ent}','sk101-{label}','person','Synthetic {label}','canonical');
        insert into reality.auth_person_bindings(auth_user_id,person_entity_id,binding_state,binding_basis) values('{user}','{ent}','active','{{"cloneFixture":true}}');
        insert into atlas.people(id,display_name,status) values('{ent}','Synthetic {label}','active');
        insert into atlas.person_auth_credentials(person_id,credential_kind,auth_user_id,status,provenance) values('{ent}','supabase_auth_user','{user}','active','{{"cloneFixture":true}}');""")
    course=uid(); other_course=uid(); unit=uid(); unit2=uid(); wrong_unit=uid(); carrier=uid(); principal=uid(); authz=uid(); cred=uid(); req=uid(); token="A"*43
    sql(f"""insert into atlas.principals(id,user_id,person_id,stable_key,name,status) values('{principal}','{owner}','{entity}','sk101-management','Synthetic owner','active');
    insert into atlas.teaching_courses(id,course_key,name,status,created_by_person_entity_id,created_by_auth_user_id,create_request_id,created_at) values('{course}','synthetic-sk101','Synthetic SK101','active','{entity}','{owner}','{req}',now());
    insert into atlas.teaching_courses(id,course_key,name,status,created_by_person_entity_id,created_by_auth_user_id,create_request_id,created_at) values('{other_course}','synthetic-sk101-other','Synthetic other Course','active','{entity}','{owner}',gen_random_uuid(),now());
    insert into atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{unit}','{course}',gen_random_uuid(),'lesson','Class 1',1024,'{entity}','{owner}',now());
    insert into atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{unit2}','{course}',gen_random_uuid(),'lesson','Class 2',2048,'{entity}','{owner}',now());
    insert into atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id,created_at) values('{wrong_unit}','{other_course}',gen_random_uuid(),'lesson','Wrong Course Unit',1,'{entity}','{owner}',now());
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
    stale={**write,"p_request":uid(),"p_payload":{"expectedTitle":"Class 1","title":"Stale title attempt"}}; stale_value=rpc("shared_delegated_course_management_write_service_v1",stale,"owner",500,"service"); check(stale_value.get("code")=="40001","stale title SQLSTATE")
    def concurrent_attempt(new_title):
        attempt={**write,"p_request":uid(),"p_expected_revision":1,"p_payload":{"expectedTitle":"Class 01 — Reality Is Readable","title":new_title}}
        return auth.rpc(api,key,"shared_delegated_course_management_write_service_v1",attempt,key)
    with ThreadPoolExecutor(max_workers=2) as pool:
        concurrent_results=list(pool.map(concurrent_attempt,["Concurrent title A","Concurrent title B"]))
    concurrent_successes=[value for status,value in concurrent_results if status==200]
    concurrent_conflicts=[value for status,value in concurrent_results if status==500]
    check(len(concurrent_successes)==1 and len(concurrent_conflicts)==1,"concurrent title race outcome")
    check(concurrent_conflicts[0].get("code")=="40001","concurrent stale SQLSTATE")
    concurrent_title=concurrent_successes[0]["title"]
    check(concurrent_title in ("Concurrent title A","Concurrent title B"),"concurrent winning title")
    check(rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit})["title"]==concurrent_title,"title readback")
    check(rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit2})["title"]==other_before,"unrelated Unit unchanged")
    rpc("shared_delegated_course_management_write_service_v1",write,"outsider",403,"person")
    # Course manuscript: replay, conflict, stale, concurrent write, and independent readback.
    m0=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"course_material_read"})
    check(m0.get("material") is None,"empty manuscript read")
    material_request=uid(); material_payload={"text":"Manuscript alpha"}
    material_write={"p_token_hash":h,"p_course":course,"p_operation":"course_material_save","p_unit":None,"p_request":material_request,"p_expected_revision":0,"p_payload":material_payload}
    material_receipt=rpc("shared_delegated_course_management_write_service_v1",material_write)
    check(rpc("shared_delegated_course_management_write_service_v1",material_write)==material_receipt,"manuscript replay")
    rpc("shared_delegated_course_management_write_service_v1",{**material_write,"p_payload":{"text":"Conflicting manuscript"}},"owner",409,"service")
    stale_material={**material_write,"p_request":uid(),"p_payload":{"text":"Stale manuscript"}}
    check(rpc("shared_delegated_course_management_write_service_v1",stale_material,"owner",500,"service").get("code")=="40001","stale manuscript SQLSTATE")
    def concurrent_material(text):
        p={**material_write,"p_request":uid(),"p_expected_revision":1,"p_payload":{"text":text}}
        return auth.rpc(api,key,"shared_delegated_course_management_write_service_v1",p,key)
    with ThreadPoolExecutor(max_workers=2) as pool:
        material_results=list(pool.map(concurrent_material,["Manuscript concurrent A","Manuscript concurrent B"]))
    material_success=[v for status,v in material_results if status==200]
    material_conflicts=[v for status,v in material_results if status==500]
    check(len(material_success)==1 and len(material_conflicts)==1 and material_conflicts[0].get("code")=="40001","manuscript concurrency")
    material_read=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"course_material_read"})
    check(material_read["material"]["text"]==material_success[0]["text"] if "text" in material_success[0] else material_read["material"]["text"] in ("Manuscript concurrent A","Manuscript concurrent B"),"manuscript readback")
    rpc("shared_delegated_course_management_write_service_v1",material_write,"outsider",403,"person")

    # Composition: the existing validator must resolve both members to this Course.
    members=[{"unitId":unit2,"classUnitId":unit,"depth":"foundational"}]
    composition_request=uid(); composition_write={"p_token_hash":h,"p_course":course,"p_operation":"composition_save","p_unit":None,"p_request":composition_request,"p_expected_revision":0,"p_payload":{"members":members}}
    composition_receipt=rpc("shared_delegated_course_management_write_service_v1",composition_write)
    check(rpc("shared_delegated_course_management_write_service_v1",composition_write)==composition_receipt,"composition replay")
    rpc("shared_delegated_course_management_write_service_v1",{**composition_write,"p_payload":{"members":[]}},"owner",409,"service")
    composition_stale={**composition_write,"p_request":uid(),"p_payload":{"members":members}}
    check(rpc("shared_delegated_course_management_write_service_v1",composition_stale,"owner",500,"service").get("code")=="40001","stale composition SQLSTATE")
    composition_read=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"composition_read"})
    check(composition_read["members"]==members and composition_read["revisionNumber"]==1,"composition readback")
    rpc("shared_delegated_course_management_write_service_v1",composition_write,"outsider",403,"person")

    # Unit ordering: ranks are normalized, replay is receipt-stable, and races are serialized.
    outline0=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_outline_read"})
    order_request=uid(); order_write={"p_token_hash":h,"p_course":course,"p_operation":"unit_move","p_unit":unit2,"p_request":order_request,"p_expected_revision":0,"p_payload":{"position":1}}
    order_receipt=rpc("shared_delegated_course_management_write_service_v1",order_write)
    check(rpc("shared_delegated_course_management_write_service_v1",order_write)==order_receipt,"ordering replay")
    rpc("shared_delegated_course_management_write_service_v1",{**order_write,"p_payload":{"position":2}},"owner",409,"service")
    stale_order={**order_write,"p_request":uid(),"p_payload":{"position":2}}
    check(rpc("shared_delegated_course_management_write_service_v1",stale_order,"owner",500,"service").get("code")=="40001","stale ordering SQLSTATE")
    def concurrent_order(unit_id,position):
        p={**order_write,"p_unit":unit_id,"p_request":uid(),"p_expected_revision":1,"p_payload":{"position":position}}
        return auth.rpc(api,key,"shared_delegated_course_management_write_service_v1",p,key)
    with ThreadPoolExecutor(max_workers=2) as pool:
        order_results=list(pool.map(lambda args: concurrent_order(*args),[(unit,2),(unit2,1)]))
    order_success=[v for status,v in order_results if status==200]
    order_conflicts=[v for status,v in order_results if status==500]
    check(len(order_success)==1 and len(order_conflicts)==1 and order_conflicts[0].get("code")=="40001","ordering concurrency")
    outline=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_outline_read"})
    positions=[x["position"] for x in outline["units"]]
    check(sorted(positions)==[1,2] and len(set(positions))==2,"ordering independent readback")
    rpc("shared_delegated_course_management_write_service_v1",order_write,"outsider",403,"person")

    # Subsection editing must carry the current text and preserve untouched surroundings.
    full_text="Keep prefix :: old middle :: keep suffix"
    subsection_request=uid(); subsection_write={"p_token_hash":h,"p_course":course,"p_operation":"unit_subsection_save","p_unit":unit2,"p_request":subsection_request,"p_expected_revision":0,"p_payload":{"baseText":"","selectionStart":0,"selectionEnd":0,"replacement":full_text}}
    subsection_receipt=rpc("shared_delegated_course_management_write_service_v1",subsection_write)
    check(rpc("shared_delegated_course_management_write_service_v1",subsection_write)==subsection_receipt,"subsection replay")
    rpc("shared_delegated_course_management_write_service_v1",{**subsection_write,"p_payload":{"baseText":"","selectionStart":0,"selectionEnd":0,"replacement":"different"}},"owner",409,"service")
    start=full_text.index("old middle"); end=start+len("old middle")
    edit_request=uid(); edit_write={"p_token_hash":h,"p_course":course,"p_operation":"unit_subsection_save","p_unit":unit2,"p_request":edit_request,"p_expected_revision":1,"p_payload":{"baseText":full_text,"selectionStart":start,"selectionEnd":end,"replacement":"new middle"}}
    edit_receipt=rpc("shared_delegated_course_management_write_service_v1",edit_write)
    edit_read=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"revision_history_read","p_unit":unit2})
    check(edit_read["revisions"][-1]["text"]=="Keep prefix :: new middle :: keep suffix","subsection preserves unrelated text")
    rpc("shared_delegated_course_management_write_service_v1",{**edit_write,"p_expected_revision":0,"p_request":uid()},"owner",500,"service")
    wrong_subsection={**subsection_write,"p_unit":wrong_unit,"p_request":uid()}
    rpc("shared_delegated_course_management_write_service_v1",wrong_subsection,"owner",403,"service")
    def concurrent_subsection(replacement):
        p={**edit_write,"p_request":uid(),"p_expected_revision":2,"p_payload":{"baseText":"Keep prefix :: new middle :: keep suffix","selectionStart":15,"selectionEnd":25,"replacement":replacement}}
        return auth.rpc(api,key,"shared_delegated_course_management_write_service_v1",p,key)
    with ThreadPoolExecutor(max_workers=2) as pool:
        subsection_results=list(pool.map(concurrent_subsection,["winner A","winner B"]))
    subsection_success=[v for status,v in subsection_results if status==200]
    subsection_conflicts=[v for status,v in subsection_results if status==500]
    check(len(subsection_success)==1 and len(subsection_conflicts)==1 and subsection_conflicts[0].get("code")=="40001","subsection concurrency")
    final_history=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"revision_history_read","p_unit":unit2})
    check(len(final_history["revisions"])==3,"subsection history")
    base_revision=final_history["revisions"][0]["revisionId"]; compare_revision=final_history["revisions"][1]["revisionId"]
    comparison=rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"revision_compare","p_unit":unit2,"p_revision":base_revision,"p_reference":compare_revision})
    check(comparison["baseRevision"]["text"]==full_text and comparison["compareRevision"]["text"]=="Keep prefix :: new middle :: keep suffix" and comparison["same"] is False,"actual revision comparison")
    recovery_request=uid(); recovery_write={"p_token_hash":h,"p_course":course,"p_operation":"revision_recover","p_unit":unit2,"p_request":recovery_request,"p_expected_revision":3,"p_payload":{"revisionId":base_revision}}
    recovery_receipt=rpc("shared_delegated_course_management_write_service_v1",recovery_write)
    check(recovery_receipt["sourceRevisionId"]==base_revision and rpc("shared_delegated_course_management_write_service_v1",recovery_write)==recovery_receipt,"historical recovery replay")
    rpc("shared_delegated_course_management_write_service_v1",{**recovery_write,"p_payload":{"revisionId":compare_revision}},"owner",409,"service")
    wrong_recovery={**recovery_write,"p_unit":wrong_unit,"p_request":uid(),"p_expected_revision":4}
    rpc("shared_delegated_course_management_write_service_v1",wrong_recovery,"owner",403,"service")
    check(rpc("shared_delegated_course_management_write_service_v1",{**recovery_write,"p_request":uid(),"p_expected_revision":3},"owner",500,"service").get("code")=="40001","stale recovery SQLSTATE")
    rpc("shared_delegated_course_management_write_service_v1",recovery_write,"outsider",403,"person")
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"course_material_read"},"outsider",403,"person")
    sql(f"update atlas.delegated_agent_authorizations set authorization_state='revoked' where id='{authz}'")
    rpc("shared_delegated_course_management_read_service_v1",{"p_token_hash":h,"p_course":course,"p_operation":"unit_title_read","p_unit":unit},"owner",403,"service")
    check(sql(f"select count(*) from atlas.teaching_course_versions where course_id='{course}'")=="0","unpublished")
    Path(a.output).write_text("PASS signed SK101 management clone\n")
    print("PASS signed SK101 management clone")
if __name__=="__main__": main()
