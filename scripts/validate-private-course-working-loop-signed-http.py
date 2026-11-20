#!/usr/bin/env python3
"""Fictional signed owner/outsider proof for the pinned Course working-loop clone.

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

spec = importlib.util.spec_from_file_location("local_auth", Path(__file__).with_name("validate-atlas-c1-signed-http.py"))
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)


def check(value, message):
    if not value:
        raise AssertionError(message)


def person(n):
    return f"f5b00000-0000-4000-8000-{n:012d}"


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
    course = rpc("shared_teaching_course_create_self_api_v1", {"p_request_id":uid(), "p_title":"Fictional SK 101"})["courseId"]
    foreign = rpc("shared_teaching_course_create_self_api_v1", {"p_request_id":uid(), "p_title":"Fictional other Course"})["courseId"]
    rpc("shared_private_atlas_carrier_enroll_standing_self_api_v1", {"p_course_id":course}, "outsider", 403)
    grant = rpc("shared_private_atlas_carrier_enroll_standing_self_api_v1", {"p_course_id":course})
    aid = grant["authorizationId"]
    check(grant["courseId"] == course and grant["endsAt"] is None and grant["state"] == "active", "standing owner grant")
    check(rpc("shared_private_atlas_carrier_enroll_standing_self_api_v1", {"p_course_id":course})["authorizationId"] == aid, "enrollment replay")
    check(rpc("shared_private_atlas_carrier_status_self_api_v2", {}, "outsider")["authorization"] is None, "outsider cannot see owner grant")
    check(rpc("shared_private_atlas_carrier_status_self_api_v2", {})["authorization"]["authorizationId"] == aid, "status readback")

    # The locally generated service key is a transport only; the credential is
    # independently issued against the signed owner's exact grant in the clone.
    import subprocess
    env = subprocess.run(["supabase", "status", "-o", "env"], capture_output=True, text=True, check=True).stdout
    local = dict(line.split("=", 1) for line in env.splitlines() if "=" in line)
    service = (local.get("SERVICE_ROLE_KEY") or local.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip().strip('"')
    check(bool(service), "local service key required")
    key_hash = "a" * 64
    def service_rpc(name, params, expected=200):
        return rpc(name, params, role=None, expected=expected, key=service)
    receipt = service_rpc("shared_private_atlas_carrier_issue_service_v1", {"p_authorization_id":aid,"p_token_hash":key_hash})
    check(receipt["authorizationId"] == aid and receipt["expiresAt"] is None, "null-expiry credential issued")
    check(service_rpc("shared_private_atlas_carrier_admit_service_v1", {"p_token_hash":key_hash}) is True, "source admission")
    outline = service_rpc("shared_delegated_course_outline_read_service_v1", {"p_token_hash":key_hash,"p_course":course})
    check(outline["courseId"] == course and outline["units"] == [], "exact empty Course outline")
    service_rpc("shared_delegated_course_outline_read_service_v1", {"p_token_hash":key_hash,"p_course":foreign}, 403)
    service_rpc("shared_delegated_course_unit_read_service_v1", {"p_token_hash":key_hash,"p_course":course,"p_unit":uid()}, 403)
    service_rpc("shared_delegated_course_outline_read_service_v1", {"p_token_hash":"b"*64,"p_course":course}, 403)
    proposal = {"contractVersion":"titus_course_authoring_proposal_v1", "courseId":course,
                "proposalId":uid(), "items":[{"operation":"append_unit", "requestId":uid(),
                "kind":"lesson", "title":"Fictional lesson", "text":"Fictional source text",
                "basis":[{"reference":"fictional-local-source", "description":"Synthetic fixture only"}]}]}
    save = {"p_token_hash":key_hash,"p_course":course,"p_proposal":proposal}
    service_rpc("shared_delegated_course_save_draft_service_v1",
                {**save,"p_course":foreign,"p_proposal":{**proposal,"courseId":foreign}}, 403)
    saved = service_rpc("shared_delegated_course_save_draft_service_v1", save)
    check(saved.get("contractVersion") is not None, "source-derived save receipt")
    check(service_rpc("shared_delegated_course_save_draft_service_v1", save) == saved, "exact replay")
    changed = {**proposal,"items":[{**proposal["items"][0],"text":"Altered fictional text"}]}
    status, _ = auth.rpc(api, service, "shared_delegated_course_save_draft_service_v1", {**save,"p_proposal":changed}, service)
    check(status in (400,403,409), "changed replay must fail")
    units = service_rpc("shared_delegated_course_outline_read_service_v1", {"p_token_hash":key_hash,"p_course":course})["units"]
    check(len(units) == 1 and units[0]["title"] == "Fictional lesson", "read saved original")
    unit = service_rpc("shared_delegated_course_unit_read_service_v1", {"p_token_hash":key_hash,"p_course":course,"p_unit":units[0]["unitId"]})
    check(unit["material"]["text"] == "Fictional source text", "read exact current material")
    service_rpc("shared_delegated_course_unit_read_service_v1", {"p_token_hash":key_hash,"p_course":foreign,"p_unit":units[0]["unitId"]}, 403)
    check(sql("SELECT count(*) FROM atlas.teaching_course_versions") == "0", "nothing published")
    rpc("shared_private_atlas_carrier_revoke_self_api_v2", {"p_authorization_id":aid}, "outsider", 403)
    check(rpc("shared_private_atlas_carrier_revoke_self_api_v2", {"p_authorization_id":aid})["state"] == "revoked", "owner revocation")
    service_rpc("shared_delegated_course_outline_read_service_v1", {"p_token_hash":key_hash,"p_course":course}, 403)
    service_rpc("shared_delegated_course_save_draft_service_v1", {**save,"p_proposal":{**proposal,"proposalId":uid()}}, 403)
    check(service_rpc("shared_private_atlas_carrier_admit_service_v1", {"p_token_hash":key_hash}) is False, "revocation blocks admission")
    check(sql("SELECT count(*) FROM atlas.teaching_courses") == "2", "same two fictional Courses only")
    Path(args.output).write_text("PASS independent signed standing Course read and revocation proof\n")
    print("PASS independent signed standing Course read and revocation proof")


if __name__ == "__main__":
    main()
