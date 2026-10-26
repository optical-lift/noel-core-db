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
                  "NULL::text AS instructions",
                  "'instructions',r.instructions",
                  "workRelevanceVerified',r.has_relevance",
                  "scheduleReadAcrossAllDates",
                  "optionalRequestsExcluded"):
    check(authority in my_work,
          f"Held original My Work authorized source cutover missing: {authority}")
check("w.title,w.instructions,w.result_contract_key" not in my_work,
      "Held original My Work reader cannot disclose unreviewed instructions")
check(not re.search(r"\\b(?:GRANT|ALTER TABLE|INSERT|DELETE|UPDATE)\\b", my_work, re.I),
      "Original My Work cutover is only a held read-source function replacement")
check("relevance.has_relevance IS TRUE" in my_work_checks and
      "NULL::text AS instructions" in my_work_checks and
      "has_function_privilege" in my_work_checks,
      "Protected-clone original My Work postconditions missing")

print("PASS Gate 0 static source guards (NOT clone/signed privacy acceptance)")
