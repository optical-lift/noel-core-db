#!/usr/bin/env python3
"""Fail-closed STATIC review of Atlas connected Person Gate 0 source candidates.

This does not connect to production, execute migration SQL, construct a signed
session, certify field/row disclosure, or authorize a release. It catches
high-cost source mistakes before protected clone + signed HTTP testing.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "candidates/atlas/connected_person_effective_disclosure_review_v1"

def check(ok: bool, msg: str) -> None:
    if not ok:
        raise AssertionError(msg)

def read(filename: str) -> str:
    return (BASE / filename).read_text(encoding="utf-8")
def sql_statements_only(value: str) -> str:
    # Ignore leading SQL safety comments, not executable mutation statements.
    return re.sub(r"(?m)^\s*--[^\n]*$", "", value)


review = read("candidate.sql")
review_tests = read("postconditions.sql")
farm = read("legacy_farm_reader_body_containment_hold.sql")
farm_tests = read("legacy_farm_reader_postconditions_hold.sql")
inventory = read("gate0_reader_inventory_readonly.sql")
notes = read("README.md")

check(review.count("BEGIN;") == 1 and review.count("COMMIT;") == 1, "review transaction shape")
check(review.count("CREATE OR REPLACE FUNCTION") == 2, "only internal source and public API wrapper allowed")
check("JOIN reality.entities subject_person" in review, "canonical source Person join missing")
check("subject_person.entity_kind='person'" in review and
      "subject_person.identity_state='canonical'" in review, "canonical Person source check missing")
for s in ("auth.uid() IS NULL", "principal_has_ledger_authority_v1",
          "ledger.seats", "seat_state='active'", "s.ended_at IS NULL",
          "verification_incomplete", "mayCertifyNonDisclosure',false", "reality_access_self_api_v1", "current_person_id_v1",
          "'not_found'", "current_principal_id_v1", "targetSeatIsNotDisclosurePermission"):
    check(s in review, f"governor-only source guard absent: {s}")
check("'atlas.zone_registry_source_v1'" not in review, "universal reviewer cannot hardcode Flower readers")
for source_guard in ("preliminaryWorkFieldReview",
                     "governor_review_inputs_only",
                     "workFieldsRequireSeparateDecisions",
                     "candidateIsNotAnEffectiveDisclosureGrant",
                     "titleFieldDecisionStatus',title_field_decision_status",
                     "instructionsFieldDecisionStatus',instructions_field_decision_status",
                     "a.assignee_canonical_person_id=p_person_entity_id",
                     "a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text",
                     "rel.ledger_id=p_ledger_id",
                     "company_work_native_ledger_exact_source_v1",
                     "LIMIT 51",
                     "hasMoreCandidateWork",
                     "mayCertifyNonDisclosure',false",
                     "titleCandidateSha256",
                     "instructionsCandidateSha256",
                     "title_dec.id",
                     "instructions_dec.id",
                     "ORDER BY e.decision_sequence DESC LIMIT 1",
                     "connected_person_work_field_source_eligible_v1"):
    check(source_guard in review,
          f"Preliminary governor-only Work field review missing source guard: {source_guard}")
check("preliminaryWorkFieldReview" in review_tests and
      "LIMIT 51" in review_tests and
      "verification_incomplete" in review_tests,
      "Governor-only field preview clone postconditions missing")
check(not re.search(r"CREATE TABLE|INSERT INTO|UPDATE atlas\.|DELETE FROM",review,re.I),
      "read-only governor review cannot mutate data")
check(review.count("GRANT EXECUTE ON FUNCTION") == 1 and
      "public.connected_person_effective_disclosure_review_self_api_v1(uuid,uuid)" in review,
      "review may grant only the exact public bridge")
for role in ("PUBLIC", "anon", "authenticated"):
    check(role in review, f"review role handling omitted: {role}")
check("has_function_privilege('anon',v_internal,'EXECUTE')" in review_tests,
      "internal ACL postcondition missing")

old_helpers = {
 "zone_registry_source_v1":"uuid",
 "object_crop_bed_map_v1":"uuid",
 "farm_care_zone_v1":"uuid,text,integer",
 "farm_snapshot_for_member_v1":"uuid",
 "farm_care_summary_v1":"uuid,integer",
 "farm_care_object_v1":"uuid,text,integer",
 "grow_room_state_v1":"uuid",
 "object_workbench_v1":"uuid,text,integer,integer",
}
check(farm.count("BEGIN;") == 1 and farm.count("COMMIT;") == 1, "farm transaction shape")
check(farm.count("CREATE OR REPLACE FUNCTION atlas.") == 9, "expected 8 read helpers and one home")
check(not re.search(r"\bGRANT\s+",farm,re.I), "old farm paths must not receive new grants")
for name,sig in old_helpers.items():
    declaration = f"CREATE OR REPLACE FUNCTION atlas.{name}("
    check(farm.count(declaration) == 1, f"function must have exactly one body: {name}")
    begin = farm.index(declaration)
    end = farm.find("CREATE OR REPLACE FUNCTION atlas.",begin+len(declaration))
    body = farm[begin:end if end!=-1 else None]
    check("atlas.is_farm_owner(" in body, f"owner-only source guard absent: {name}")
    check("Resource not found." in body, f"missing/unauthorized indistinguishability absent: {name}")
    check(f"REVOKE EXECUTE ON FUNCTION atlas.{name}({sig}) FROM PUBLIC,anon,authenticated;" in farm,
          f"direct authenticated SQL route not revoked: {name}")
    check(f"atlas.{name}({sig})" in farm_tests,
          f"clone ACL/guard test missing: {name}")
check(farm.count("CREATE OR REPLACE FUNCTION atlas.universal_home_v1(")==1,
      "legacy universal home must be handled together with snapshot")
home=farm.split("CREATE OR REPLACE FUNCTION atlas.universal_home_v1(",1)[1].split(
    "CREATE OR REPLACE FUNCTION atlas.",1)[0]
check(home.count("and fm.role = 'owner'")==2,
      "both old universal home farm membership selectors must be guarded")
check("atlas.farm_snapshot_for_member_v1(v_farm.farm_id)" in home,
      "legacy home dependency must remain explicitly visible")
check("length('and fm.role = ''owner''') <> 2" in farm_tests,
      "actual two owner-role selectors must be asserted in clone test")
check("SELECT *" in inventory or "SELECT " in inventory,
      "replay inventory missing")
check("DO NOT" in notes.upper() and "signed" in notes.lower(), "release safety status missing")

work = read("connected_person_work_read_candidate.sql")
work_tests = read("connected_person_work_read_postconditions.sql")
check(work.count("CREATE OR REPLACE FUNCTION") == 2, "only internal Work reader and public wrapper allowed")
check(work.count("BEGIN;") == 1 and work.count("COMMIT;") == 1, "Work source transaction shape")
for authority in ("reality_access_self_api_v1", "current_person_id_v1",
                  "ledger.seats", "s.ended_at IS NULL",
                  "person_has_native_ledger_connection_v1",
                  "company_work_native_ledger_relevance",
                  "company_work_native_ledger_exact_source_v1",
                  "rel.attribution_state='active'",
                  "a.assignee_canonical_person_id=v_person_id",
                  "a.state='active'", "a.assignee_membership_id IS NULL",
                  "w.work_state='open'", "not_found",
                  "permissionAuditComplete',false"):
    check(authority in work, f"Work reader must source-check {authority}")
for disallowed in ("w.instructions", "w.metadata", "growing_objects", "crop_cycles",
                   "care_state_history", "work_item_context_links",
                   "object_crop_bed_map_v1", "zone_registry_source_v1"):
    check(disallowed not in work, f"Work reader must not expose {disallowed}")
check(work.count("GRANT EXECUTE ON FUNCTION") == 1, "Work source grant only for public API")
check("TO authenticated;" in work and "FROM PUBLIC,anon,authenticated;" in work,
      "Work API ACL needs explicit roles")
check("to_regprocedure" in work_tests and "has_function_privilege" in work_tests,
      "Work protected-clone postconditions missing")

my_work = read("connected_person_my_work_existing_reader_cutover_hold.sql")
my_work_checks = read("connected_person_my_work_existing_reader_cutover_postconditions_hold.sql")
check(my_work.count("CREATE OR REPLACE FUNCTION") == 1,
      "Held old My Work cutover may replace only the original internal source")
check(my_work.count("BEGIN;") == 1 and my_work.count("COMMIT;") == 1,
      "Held old My Work cutover transaction shape")
check("connected_person_my_work_self_api_v1(p_limit integer" in my_work,
      "Must retain the existing My Work signature and public wrapper")
for authority in ("reality_access_self_api_v1",
                  "v_session_access->'person'->>'id'",
                  "current_person_id_v1",
                  "person_has_native_ledger_connection_v1",
                  "company_work_native_ledger_relevance",
                  "company_work_native_ledger_exact_source_v1",
                  "AND relevance.has_relevance IS TRUE",
                  "connected_person_work_field_currently_approved_v1",
                  "'instructions',r.instructions",
                  "workRelevanceVerified',r.has_relevance",
                  "scheduleReadAcrossAllDates",
                  "optionalRequestsExcluded"):
    check(authority in my_work,
          f"Held original My Work authorized source cutover missing: {authority}")
check("w.title,w.instructions,w.result_contract_key" not in my_work,
      "Held original My Work reader cannot disclose unreviewed instructions")
check(not re.search(r"\b(?:GRANT|ALTER TABLE|INSERT|DELETE|UPDATE)\b", sql_statements_only(my_work), re.I),
      "Original My Work cutover is only a held read-source function replacement")
check("relevance.has_relevance IS TRUE" in my_work_checks and
      "connected_person_work_field_currently_approved_v1" in my_work_checks and
      "has_function_privilege" in my_work_checks,
      "Protected-clone original My Work postconditions missing")

# The OTHER already-shipped connected Person all-date Today source is also
# directly callable. A narrow replacement My Work API is not a privacy fix
# until these original public source routes are cut over together.
native_today = read("connected_person_today_existing_reader_cutover_hold.sql")
native_today_checks = read("connected_person_today_existing_reader_cutover_postconditions_hold.sql")
check(native_today.count("CREATE OR REPLACE FUNCTION") == 1,
      "Today cutover may replace only the original internal reader")
check(native_today.count("BEGIN;") == 1 and native_today.count("COMMIT;") == 1,
      "Today cutover must have one source transaction")
for part in ("connected_person_company_work_today_self_api_v1(p_limit integer",
             "reality_access_self_api_v1",
             "person_has_native_ledger_connection_v1",
             "company_work_native_ledger_relevance",
             "company_work_native_ledger_exact_source_v1",
             "a.assignee_membership_id IS NULL",
             "rel.attribution_state='active'",
             "connected_person_work_field_currently_approved_v1",
             "NULL::uuid AS source_id",
             "NULL::text AS source_type",
             "NULL::text AS source_date",
             "connected_person_company_work_today_v1"):
    check(part in native_today, f"Existing Person Today cutover missing {part}")
for leak in ("w.title,w.instructions", "w.source_object_type source_type",
             "w.source_object_id source_id"):
    check(leak not in native_today, f"Today still directly returns private source fields: {leak}")
check("company_work_native_ledger_relevance" in native_today_checks and
      "has_function_privilege" in native_today_checks,
      "Existing Today clone checks missing source and ACL constraints")
check(not re.search(r"\b(?:GRANT|ALTER TABLE|INSERT|DELETE|UPDATE)\b", sql_statements_only(native_today), re.I),
      "Original Today cutover cannot write data, grant permissions or edit any table")

# The dated Work route is a third separately exposed original API.
dated_work = read("connected_person_dated_work_existing_reader_cutover_hold.sql")
dated_work_checks = read("connected_person_dated_work_existing_reader_cutover_postconditions_hold.sql")
check(dated_work.count("CREATE OR REPLACE FUNCTION") == 1,
      "Held dated Work cutover may replace only its original private implementation")
check(dated_work.count("BEGIN;") == 1 and dated_work.count("COMMIT;") == 1,
      "Held dated Work replacement needs exact one-transaction shape")
for required in ("connected_person_company_work_day_self_api_v1(p_date date)",
                 "reality_access_self_api_v1",
                 "person_has_native_ledger_connection_v1",
                 "company_work_native_ledger_relevance",
                 "company_work_native_ledger_exact_source_v1",
                 "rel.attribution_state='active'",
                 "a.assignee_membership_id IS NULL",
                 "p.plan_state='completed'",
                 "w.work_state='completed'",
                 "res.acceptance_decision",
                 "connected_person_work_field_currently_approved_v1",
                 "NULL::text,",
                 "connected_person_company_work_day_v1"):
    check(required in dated_work,
          f"Held dated Work original identity/field guard missing: {required}")
for leak in ("'instructions',w.instructions",
             "w.metadata->>'taskClassification'"):
    check(leak not in dated_work, f"Held dated Work leaks institutional text: {leak}")
check("has_function_privilege" in dated_work_checks and
      "res.acceptance_decision" in dated_work_checks and
      "company_work_native_ledger_exact_source_v1" in dated_work_checks,
      "Dated Work protected-clone postconditions missing")
check(not re.search(r"\b(?:GRANT|ALTER TABLE|INSERT|DELETE|UPDATE)\b",
                    sql_statements_only(dated_work), re.I),
      "Held dated Work may not mutate Work, permissions or source tables")

# Governor approval is append-only, exact Person + Ledger + Work + field,
# content-hash bound and automatically invalidated by scope/content changes.
fields = read("connected_person_work_field_decisions_hold.sql")
fields_postconditions = read("connected_person_work_field_decisions_postconditions_hold.sql")
check("connected_person_work_field_decision_events_v1" in fields_postconditions
      and "pg_get_functiondef" in fields_postconditions
      and "has_table_privilege" in fields_postconditions
      and "has_function_privilege" in fields_postconditions,
      "Exact Work field protected-clone structural postconditions are required")
for field_guard in (
    "CREATE TABLE atlas.connected_person_work_field_decision_events_v1",
    "request_id uuid NOT NULL UNIQUE",
    "decision IN ('allow','deny')",
    "ENABLE ROW LEVEL SECURITY",
    "connected_person_work_field_source_eligible_v1",
    "connected_person_work_field_currently_approved_v1",
    "v_access:=atlas.reality_access_self_api_v1()",
    "principal_has_ledger_authority_v1",
    "pg_catalog.sha256",
    "pg_catalog.pg_advisory_xact_lock",
    "p_request_id",
    "p_expected_value_sha256",
    "v_hash IS DISTINCT FROM p_expected_value_sha256",
    "decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE",
    "ORDER BY e.decision_sequence DESC",
    "approved_value_sha256",
    "connected_person_work_field_decisions_append_only_v1",
    "valid_until",
    "governor_principal_id",
    "sourceFieldDecisionsEnforced",
    "RETURN jsonb_build_object('ok',false,'code','not_found')",
):
    check(field_guard in fields, f"Exact native Work field grant safeguard absent: {field_guard}")
check("atlas.organization_memberships" not in fields and
      "atlas.farm_memberships" not in fields and
      "employee_seat" not in fields.lower(),
      "Native Person Work field rights must not depend on deprecated employee seats")
check("GRANT EXECUTE ON FUNCTION\n public.connected_person_work_approved_fields_self_api_v1" in fields
      and "TO authenticated;" in fields,
      "Approved Work reader must have explicit authenticated bridge grant")
strict = read("connected_person_work_read_candidate.sql")
check("connected_person_work_field_currently_approved_v1" in strict,
      "New narrow reader cannot leak unapproved Work title")
for source_file in (my_work,native_today,dated_work):
    check("'title')" in source_file and "'instructions')" in source_file,
          "Every existing Work reader must respect independent source title/instruction decision")

# Held legacy Worker Day retirement must never be applied without a positive
# native Person Work/details/results substitute. This is only an ACL plan.
legacy_worker = read("legacy_worker_day_public_route_retirement_hold.sql")
legacy_worker_checks = read("legacy_worker_day_public_route_retirement_postconditions_hold.sql")
worker_routes = (
    "company_work_worker_day_self_api_v1(date,integer)",
    "company_work_worker_day_refresh_self_api_v1(date,integer)",
    "worker_report_company_work_projection_self_api_v1(uuid,text,text,jsonb)",
    "company_work_employee_home_self_api_v1()",
)
check(legacy_worker.count("REVOKE EXECUTE ON FUNCTION") == 2*len(worker_routes),
      "Worker Day retirement must close both original public and internal SQL routes")
for sig in worker_routes:
    for schema in ("public", "atlas"):
        check(f"REVOKE EXECUTE ON FUNCTION {schema}.{sig}" in legacy_worker,
              f"Original Worker Day route still executable at the cutover: {schema}.{sig}")
    check(sig in legacy_worker_checks,
          f"Clone Worker Day RPC revocation check missing for {sig}")
check("has_function_privilege('authenticated',v_public,'EXECUTE')" in legacy_worker_checks and
      "has_function_privilege('anon',v_internal,'EXECUTE')" in legacy_worker_checks,
      "Worker Day retired RPC ACL clone checks missing")
check("DO NOT EXECUTE" in legacy_worker and
      "positive" in legacy_worker.lower() and
      "parity" in legacy_worker.lower(),
      "Worker Day retirement must remain blocked on native worker parity")
check("GRANT EXECUTE" not in legacy_worker and
      "CREATE OR REPLACE FUNCTION" not in legacy_worker and
      "DROP FUNCTION" not in legacy_worker,
      "Worker Day ACL hold cannot add privileges, replace source or remove history")

# Production testing for now is an actual READ-ONLY catalog/audit receipt,
# NOT installed authorization SQL or proof of an independently signed worker.
production_catalog=read("production_catalog_compatibility_readonly_20261026.sql")
catalog_body=sql_statements_only(production_catalog)
check(production_catalog.count("SELECT ")>=4 and
      "pg_catalog.pg_attribute" in production_catalog and
      "auth.sessions" in production_catalog and
      "work_state" in production_catalog,
      "Production catalog audit must preserve function, table and history checks")
check(not re.search(r"\\b(?:INSERT|UPDATE|DELETE|MERGE|TRUNCATE|CREATE|ALTER|DROP|"
                    r"GRANT|REVOKE|BEGIN|COMMIT|CALL|DO|COPY)\\b",
                    catalog_body,re.I),
      "Production compatibility catalog must remain read-only")
check("blocked before execution" in notes and
      "production_catalog_compatibility_readonly_20261026.sql" in notes,
      "Release notes must not claim blocked rollback compile or signed access pass")

print("PASS Gate 0 static source guards (NOT clone/signed privacy acceptance)")
