#!/usr/bin/env python3
"""Fictional signed proof for held SK 101 standing management.

Run only against an isolated PG17 clone of the released schema.
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
    enroll = "shared_private_atlas_carrier_enroll_standing_management_self_api_v1"
    revoke = "shared_private_atlas_carrier_revoke_standing_management_self_api_v1"
    read, write = "teaching.course.management.read", "teaching.course.management.write"
    legacy_admit = "shared_private_atlas_carrier_admit_service_v1"
    management_admit = "shared_private_atlas_carrier_admit_management_service_v1"
    read_rpc = "shared_delegated_course_management_read_service_v1"
    write_rpc = "shared_delegated_course_management_write_service_v1"

    def admitted(command, target=course):
        return srv(management_admit, {"p_token_hash": legacy_hash, "p_command": command, "p_course": target})

    def draft(operation, target_unit=None):
        return srv(read_rpc, {"p_token_hash": legacy_hash, "p_course": course,
                              "p_operation": operation, "p_unit": target_unit})

    def packet(operation, revision, payload, target_unit=None):
        return {"p_token_hash": legacy_hash, "p_course": course, "p_operation": operation,
                "p_unit": target_unit, "p_request": uid(), "p_expected_revision": revision,
                "p_payload": payload}

    check(srv(legacy_admit, {"p_token_hash": legacy_hash}) is True, "legacy admitted")
    check(not admitted(read) and not admitted(write), "credential alone has no management authority")
    rpc(enroll, {"p_course": course, "p_command": read}, "outsider", 403)
    rpc(enroll, {"p_course": foreign, "p_command": read}, expected=400)
    rpc(enroll, {"p_course": course, "p_command": "teaching.course.authoring.save_draft"}, expected=400)
    with ThreadPoolExecutor(max_workers=2) as pool:
        access = list(pool.map(lambda _: rpc(enroll, {"p_course": course, "p_command": read}), range(2)))
    check(access[0]["authorizationId"] == access[1]["authorizationId"], "serialized enrollment")
    check(admitted(read) and not admitted(write) and not admitted(read, foreign), "independent exact read grant")
    write_id = rpc(enroll, {"p_course": course, "p_command": write})["authorizationId"]
    check(srv(legacy_admit, {"p_token_hash": legacy_hash}) is True, "legacy survives standing enrollment")

    unit2 = uid()
    sql(f"""INSERT INTO atlas.teaching_course_units(unit_id,course_id,create_request_id,kind,title,display_position,
      created_by_person_entity_id,created_by_auth_user_id)
      VALUES('{unit2}','{course}',gen_random_uuid(),'lesson','Second',2,'{person(101)}','{person(1)}')""")
    activity = uid()
    first_body = f"## Question {{#titus-activity:{activity}}}\n\nWhat belongs to the first edition?"
    seed = srv(write_rpc, packet("unit_subsection_save", 0, {
        "baseText": "", "selectionStart": 0, "selectionEnd": 0, "replacement": first_body}, unit))
    srv(write_rpc, packet("course_material_save", 0, {"text": "First edition manuscript"}))
    publish = "shared_teaching_course_definition_publish_self_api_v1"
    seal = "shared_teaching_course_curriculum_seal_self_api_v1"
    publication = {"p_course_id": course, "p_request_id": uid(), "p_title": "Fictional edition one",
                   "p_summary": "Disposable clone.", "p_outcomes": ["Verify published edition isolation."]}
    version = str(uuid.UUID(rpc(publish, publication)["courseVersionId"]))
    sealed = rpc(seal, {"p_course_id": course, "p_course_version_id": version, "p_request_id": uid()})
    snapshot = str(uuid.UUID(sealed["snapshotId"]))

    invitation = rpc("shared_teaching_private_study_invite_self_api_v1", {
        "p_course_id": course, "p_learner_person_entity_id": person(102),
        "p_request_id": uid(), "p_expires_at": None})["invitationId"]
    rpc("shared_teaching_private_study_respond_self_api_v1", {
        "p_invitation_id": invitation, "p_request_id": uid(), "p_decision": "accept"}, "outsider")
    rpc("shared_teaching_private_study_unit_decide_self_api_v1", {
        "p_invitation_id": invitation, "p_unit_id": unit, "p_request_id": uid(),
        "p_decision": "allow", "p_course_version_id": version})
    answer = {"p_invitation": invitation, "p_unit": unit, "p_snapshot": snapshot,
              "p_unit_revision": seed["revisionId"], "p_activity": activity}
    saved = rpc("shared_teaching_private_study_answer_save_self_api_v1", {
        **answer, "p_request": uid(), "p_expected_revision": 0,
        "p_text": "A fictional answer to the sealed question."}, "outsider")
    submission = rpc("shared_teaching_private_answer_submit_self_api_v1", {
        "p_answer_revision_id": saved["answerRevisionId"], "p_reviewer_person_id": person(101),
        "p_request_id": uid()}, "outsider")["submissionId"]

    def published_state():
        return {
            "snapshot": sql(f"SELECT curriculum_payload::text FROM atlas.teaching_course_version_curriculum_snapshots WHERE snapshot_id='{snapshot}'"),
            "delivery": rpc("shared_teaching_private_study_delivery_self_api_v1", {"p_course_id": course}),
            "index": rpc("shared_teaching_private_study_index_self_api_v1", {"p_invitation_id": invitation}, "outsider"),
            "unit": rpc("shared_teaching_private_study_sealed_unit_read_self_api_v1", {
                "p_invitation_id": invitation, "p_unit_id": unit}, "outsider"),
            "answer": rpc("shared_teaching_private_study_answer_read_self_api_v1", answer, "outsider"),
            "context": rpc("shared_teaching_private_answer_question_context_self_api_v1", {
                "p_submission_id": submission, "p_mode": "learner"}, "outsider"),
        }

    before = published_state()
    check("What belongs to the first edition?" in before["snapshot"], "first edition has substantive material")
    check(srv(legacy_admit, {"p_token_hash": legacy_hash}) is False, "released legacy write fence after seal")
    check(admitted(read) and admitted(write), "standing read and write after seal")

    def mutate(request):
        result = srv(write_rpc, request)
        check(srv(write_rpc, request) == result, "exact request replay")
        check(published_state() == before, f"sealed edition changed after {request['p_operation']}")
        return result

    mutate(packet("course_title_save", 0, {"expectedTitle": "Fictional SK101", "title": "Draft title"}))
    check(draft("course_title_read")["title"] == "Draft title", "Course title readback")
    mutate(packet("unit_title_save", 0, {"expectedTitle": "Original", "title": "Draft Unit"}, unit))
    check(draft("unit_title_read", unit)["title"] == "Draft Unit", "Unit title readback")
    mutate(packet("course_material_save", 1, {"text": "Second draft manuscript"}))
    check(draft("course_material_read")["material"]["text"] == "Second draft manuscript", "manuscript readback")
    mutate(packet("unit_move", 0, {"position": 1}, unit2))
    check(draft("unit_outline_read")["units"][0]["unitId"] == unit2, "ordering readback")
    members = [{"unitId": unit2, "classUnitId": unit, "depth": "foundational"}]
    mutate(packet("composition_save", 0, {"members": members}))
    check(draft("composition_read")["members"] == members, "composition readback")
    removal = packet("composition_save", 1, {"members": []})
    srv(write_rpc, removal, 403)
    confirmation = {"p_course": course, "p_request": removal["p_request"], "p_base_revision": 1,
                    "p_members": []}
    confirm = "shared_sk101_confirm_composition_removal_self_api_v1"
    rpc(confirm, confirmation, "outsider", 403)
    rpc(confirm, confirmation, expected=204)
    mutate(removal)
    check(draft("composition_read")["members"] == [], "confirmed removal readback")

    mutate(packet("unit_subsection_save", 1, {"baseText": first_body, "selectionStart": 0,
                 "selectionEnd": len(first_body), "replacement": "Draft-only Unit text"}, unit))
    recovered = mutate(packet("revision_recover", 2, {"revisionId": seed["revisionId"]}, unit))
    check(recovered["sourceRevisionId"] == seed["revisionId"], "historical revision recovery")

    competitors = [packet("course_material_save", 2, {"text": title}) for title in ("Winner A", "Winner B")]
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(lambda args: auth.rpc(api, service, write_rpc, args, service), competitors))
    check(sorted(status for status, _ in outcomes) == [200, 500] and
          any(value.get("code") == "40001" for status, value in outcomes if status == 500),
          "concurrent stale revision rejected")
    check(published_state() == before, "concurrent draft writes preserve edition one")

    rpc(revoke, {"p_authorization": write_id, "p_command": write})
    check(not admitted(write) and admitted(read), "write revocation preserves standing read")
    rpc(revoke, {"p_authorization": access[0]["authorizationId"], "p_command": read})
    check(not admitted(read) and not admitted(write), "both standing grants revoked")
    check(srv(legacy_admit, {"p_token_hash": legacy_hash}) is False, "revocation does not reopen legacy write")
    check(published_state() == before, "revocation preserves edition one")

    # This partial probe cannot issue a pass receipt until independent learner
    # views and exact-revision subsequent publication assertions are in place.
    raise AssertionError("standing probe incomplete: learner and subsequent edition checks required")


if __name__ == "__main__":
    main()
