#!/usr/bin/env python3
"""Fictional signed owner/outsider proof for the SK 101 admission transition.

The protected runner installs the combined candidate into its own PG17 clone.
This probe has no hosted database credentials and creates no real grant.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import time
import uuid

helper = Path(__file__).with_name("validate-atlas-c1-signed-http.py")
if not helper.is_file():
    helper = Path(__file__).resolve().parents[2] / "scripts" / helper.name
spec = importlib.util.spec_from_file_location("local_auth", helper)
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)


def check(value, message):
    if not value:
        raise AssertionError(message)


def person(n):
    return "59e9fd9d-e7fd-48ca-91e0-ee271c05148e" if n == 101 else f"f5b00000-0000-4000-8000-{n:012d}"


def uid():
    return str(uuid.uuid4())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--db-url", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    check(re.fullmatch(r"postgresql://postgres:postgres@127[.]0[.]0[.]1:[0-9]+/postgres", args.db_url), "isolated loopback PG required")
    check(not any(os.getenv(k) for k in ("NOEL_CORE_DATABASE_URL", "DATABASE_URL", "SUPABASE_DB_URL", "SUPABASE_ACCESS_TOKEN", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY")), "hosted credentials forbidden")
    sql = lambda statement: auth.sql(args.db_url, statement)
    check(sql("SELECT current_setting('server_version_num')::int/10000") == "17", "PG17 required")
    check(sql("SELECT NOT EXISTS(SELECT 1 FROM auth.users) AND NOT EXISTS(SELECT 1 FROM atlas.teaching_courses) AND NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_authorizations)") == "t", "schema-only fixture required")
    # A production schema dump has no command registry rows. Recreate only the
    # exact already-released command definition for this local fictional test;
    # never infer grant authority from the SQL function's mere existence.
    check(sql("SELECT count(*) FROM atlas.agent_command_definitions WHERE command_key='teaching.course.authoring.save_draft'") == "0", "no inherited command fixture")
    sql("""INSERT INTO atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,
      confirmation_requirement,handler_key,status,input_contract,target_contract)
      VALUES('teaching.course.authoring.save_draft',1,'Save private Course working draft','personal','commit',
      'none','teaching.course.authoring.save_draft.v1','active',
      '{"contractVersion":"titus_course_authoring_proposal_v1","maxItems":12}'::jsonb,'{"kind":"teaching_course"}'::jsonb)""")
    for name, n in (("course-owner", 1), ("course-outsider", 2)):
        user, entity = person(n), person(n + 100)
        email = f"atlas-c1-{name}@example.invalid"
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
    sql(f"""INSERT INTO titus.course_authoring_access_grants(person_entity_id,grant_source_auth_user_id,
      grant_kind,grant_source_receipt,state,granted_at) VALUES('{person(101)}','{person(1)}',
      'private_pilot','fictional-private-course-clone','active',now());
      INSERT INTO atlas.delegated_agent_carriers(stable_key,display_name,carrier_kind,provider_key,metadata)
      VALUES('chatgpt_atlas_private','Fictional private Atlas carrier','ai_agent','openai',
      jsonb_build_object('pluginId','plugin_asdk_app_sites_4c5c75d7fb808191a0f80e42ba2ce6e1',
      'ownerPrincipalId','{person(201)}'));
      NOTIFY pgrst,'reload schema';""")
    api, anon = auth.local_status()
    tokens = {}
    for name, n in (("owner", 1), ("outsider", 2)):
        token, claims = auth.sign_in(api, anon, "course-" + name)
        check(claims["sub"] == person(n), "independent signed identity")
        check(sql(f"SELECT count(*) FROM auth.sessions WHERE id='{uuid.UUID(claims['session_id'])}' AND user_id='{person(n)}'") == "1", "persisted independent GoTrue session")
        tokens[name] = token

    def rpc(name, params, role="owner", expected=200, key=anon):
        status, value = auth.rpc(api, key, name, params, tokens.get(role) if role else key)
        check(status == expected, f"{name}: expected {expected}, got {status}: {value}")
        if expected == 403:
            check(isinstance(value, dict) and value.get("code") == "42501", f"{name}: SQL authority denial required")
        return value

    for _ in range(20):
        status, _ = auth.rpc(api, anon, "shared_private_atlas_carrier_status_self_api_v2", {}, tokens["owner"])
        if status == 200:
            break
        time.sleep(.5)
    else:
        raise AssertionError("local REST schema not ready")
    check(rpc("titus_authoring_access_self_api_v1", {})["canUseTitus"] is True, "owner authoring")
    check(rpc("titus_authoring_access_self_api_v1", {}, "outsider")["canUseTitus"] is False, "outsider no authoring")
    course = "2763f907-fdce-47d2-8308-3cd42c2d2e35"
    foreign, unit, wrong_unit = uid(), uid(), uid()
    sql(f"""INSERT INTO atlas.teaching_courses(id,course_key,name,status,created_by_person_entity_id,created_by_auth_user_id,create_request_id)
      VALUES('{course}','fixture-sk101','Fictional SK101','active','{person(101)}','{person(1)}',gen_random_uuid()),
            ('{foreign}','fixture-unrelated','Fictional other Course','active','{person(101)}','{person(1)}',gen_random_uuid());
      INSERT INTO atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,created_by_person_entity_id,created_by_auth_user_id)
      VALUES('{unit}','{course}',gen_random_uuid(),'lesson','Original',1,'{person(101)}','{person(1)}'),
            ('{wrong_unit}','{foreign}',gen_random_uuid(),'lesson','Keep this',1,'{person(101)}','{person(1)}');
      INSERT INTO atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,confirmation_requirement,handler_key,status,input_contract,target_contract)
      VALUES('teaching.course.management.read',1,'Fixture read','personal','read','none','teaching.course.management.read.v1','active','{{}}','{{"kind":"teaching_course"}}'),
            ('teaching.course.management.write',1,'Fixture write','personal','commit','none','teaching.course.management.write.v1','active','{{}}','{{"kind":"teaching_course"}}');""")
    import subprocess
    from concurrent.futures import ThreadPoolExecutor
    env = subprocess.run(["supabase", "status", "-o", "env"], capture_output=True, text=True, check=True).stdout
    local = dict(line.split("=", 1) for line in env.splitlines() if "=" in line)
    service = (local.get("SERVICE_ROLE_KEY") or local.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip().strip('"')
    check(bool(service), "local service key required")
    def srv(name, params, expected=200):
        return rpc(name, params, role=None, key=service, expected=expected)
    legacy = rpc("shared_private_atlas_carrier_enroll_standing_self_api_v1", {"p_course_id":course})["authorizationId"]
    legacy_hash = "a"*64
    srv("shared_private_atlas_carrier_issue_service_v1", {"p_authorization_id":legacy,"p_token_hash":legacy_hash})
    enroll = "shared_private_atlas_carrier_enroll_management_self_api_v1"
    read, write = "teaching.course.management.read", "teaching.course.management.write"
    expiry = sql("select (clock_timestamp()+interval '5 minutes')::text")
    def enrollment(command, **updates):
        return {"p_course":course,"p_command":command,"p_ends_at":expiry,**updates}
    rpc(enroll,enrollment(read),"outsider",403)
    rpc(enroll,enrollment(read,p_course=foreign),expected=400)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _:rpc(enroll,enrollment(read)),range(2)))
    check(results[0]["authorizationId"] == results[1]["authorizationId"] and sorted(x["replayed"] for x in results)==[False,True],"serialized signed replay")
    ids = {read:results[0]["authorizationId"],write:rpc(enroll,enrollment(write))["authorizationId"]}
    hashes = {read:"b"*64,write:"c"*64}
    issue = "shared_private_atlas_carrier_issue_management_service_v1"
    admit = "shared_private_atlas_carrier_admit_management_service_v1"
    for command in (read,write):
        issue_args = {"p_authorization":ids[command],"p_command":command,"p_token_hash":hashes[command]}
        first = srv(issue,issue_args)
        check(srv(issue,issue_args)["credentialId"]==first["credentialId"],"credential exact replay")
        srv(issue,{**issue_args,"p_token_hash":legacy_hash},403)
    check(rpc("shared_private_atlas_carrier_enroll_standing_self_api_v1",{"p_course_id":course})["authorizationId"]==legacy,"legacy enrollment survives")
    check(len(rpc("shared_private_atlas_carrier_management_status_self_api_v1",{})["authorizations"])==2,"signed management status")
    def admission(cmd, key=None, target=course):
        return srv(admit,{"p_command":cmd,"p_token_hash":key or hashes[cmd],"p_course":target})
    def check_legacy(expected=True):
        check(srv("shared_private_atlas_carrier_admit_service_v1",{"p_token_hash":legacy_hash}) is expected,"legacy admission isolation")
    check_legacy()
    check(not admission(read,hashes[write]) and not admission(write,hashes[read]) and not admission(read,legacy_hash) and not admission(read,target=foreign),"wrong credential or Course")
    check(admission(read) and admission(write),"both management authorities admitted")
    read_rpc="shared_delegated_course_management_read_service_v1"
    write_rpc="shared_delegated_course_management_write_service_v1"
    get={"p_token_hash":hashes[read],"p_course":course,"p_operation":"unit_title_read","p_unit":unit}
    srv(read_rpc,{**get,"p_unit":wrong_unit},403)
    srv(read_rpc,{**get,"p_token_hash":hashes[write]},403)
    request={"p_token_hash":hashes[write],"p_course":course,"p_operation":"unit_title_save","p_unit":unit,"p_request":uid(),"p_expected_revision":0,"p_payload":{"expectedTitle":"Original","title":"Edited"}}
    srv(write_rpc,{**request,"p_token_hash":hashes[read]},403)
    first=srv(write_rpc,request)
    check(srv(write_rpc,request)==first and srv(read_rpc,get)["title"]=="Edited","exact receipt and readback")
    srv(write_rpc,{**request,"p_payload":{"expectedTitle":"Original","title":"Conflicting"}},409)
    stale={**request,"p_request":uid(),"p_payload":{"expectedTitle":"Original","title":"Stale title attempt"}}
    status,value=auth.rpc(api,service,write_rpc,stale,service)
    check(status==500 and isinstance(value,dict) and value.get("code")=="40001",
          f"stale title write: expected HTTP 500 and SQLSTATE 40001, got {status}: {value}")
    check(srv(read_rpc,get)["title"]=="Edited","stale title write preserves winner")
    # Force a deterministic rate-limit witness irrespective of minute rollover.
    seconds = int(sql("select floor(extract(epoch from clock_timestamp()))::int % 60"))
    if seconds >= 55:
        time.sleep(61-seconds)
    sql(f"""UPDATE atlas.delegated_agent_credentials SET metadata=jsonb_set(metadata,'{{privateCarrierAdmissionV1}}',
      jsonb_build_object('window',floor(extract(epoch from clock_timestamp())/60),'count',12))
      WHERE authorization_id='{ids[read]}'""")
    check(not admission(read) and admission(write),"per-credential rate limit")
    revoke="shared_private_atlas_carrier_revoke_management_self_api_v1"
    rpc(revoke,{"p_authorization":ids[read],"p_command":read},"outsider",403)
    rpc(revoke,{"p_authorization":ids[read],"p_command":read})
    srv(read_rpc,get,403)
    check(admission(write),"read revocation preserves write")
    check_legacy()
    rpc(revoke,{"p_authorization":ids[write],"p_command":write})
    srv(write_rpc,request,403)
    check_legacy()
    replacement=rpc(enroll,enrollment(read))["authorizationId"]
    srv(issue,{"p_authorization":replacement,"p_command":read,"p_token_hash":"d"*64})
    rpc("shared_private_atlas_carrier_revoke_self_api_v2",{"p_authorization_id":legacy})
    check_legacy(False)
    check(admission(read,"d"*64),"legacy revocation preserves management")
    sql(f"UPDATE atlas.delegated_agent_credentials SET expires_at=clock_timestamp()-interval '1 second' WHERE authorization_id='{replacement}'")
    check(not admission(read,"d"*64),"expired credential denied")
    check(sql(f"SELECT title FROM atlas.teaching_course_units WHERE unit_id='{wrong_unit}'")=="Keep this","unrelated Unit preserved")
    Path(args.output).write_text("PASS signed enrollment, concurrency, three authorities, replay, exact scope, independent revocation, expiration and rate limit\n")


if __name__ == "__main__":
    main()
