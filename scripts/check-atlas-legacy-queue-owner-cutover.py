#!/usr/bin/env python3
"""Held source-contract only. NOT genuine signed authority or full-schema SQL proof."""
from pathlib import Path
s=Path(__file__).resolve().parents[1].joinpath("candidates/atlas/atlas_legacy_queue_owner_canonical_work_cutover_v1/candidate.sql").read_text()
require=[
"BEGIN;","COMMIT;","atlas.company_work_native_ledger_owner_self_v1(",
"atlas.company_work_legacy_task_reviews_v1","atlas.work_items",
"atlas.company_work_native_ledger_relevance",
"q.task_id IS DISTINCT FROM p_expected_task_id",
"q.updated_at IS DISTINCT FROM p_expected_queue_updated_at",
"p_decision NOT IN ('matched_existing_work','not_current')",
"source_object_type IN ('legacy_task','legacy_task_slice')",
"newWorkCreated',false","queueStateChanged',false",
"noTaskMeansSeparateOriginalNeedReview","queueDisagreesWithOldTask",
"FOR SHARE OF item","USING ERRCODE='42501'",
"REVOKE ALL ON FUNCTION","GRANT EXECUTE ON FUNCTION",
"TO authenticated;"
]
for token in require: assert token in s,token
assert s.count("CREATE OR REPLACE FUNCTION atlas.")==2
assert s.count("CREATE OR REPLACE FUNCTION public.")==2
assert s.count("LANGUAGE sql STABLE SET search_path TO ''")==1
assert s.count("LANGUAGE sql SET search_path TO ''")==1
assert s.count("REVOKE ALL ON FUNCTION public.")==2
assert s.count("GRANT EXECUTE ON FUNCTION public.")==2
assert "SECURITY DEFINER" not in s.split("CREATE OR REPLACE FUNCTION public.",1)[1].split("REVOKE ALL ON FUNCTION",1)[0]
assert "INSERT INTO atlas.work_items" not in s
assert "INSERT INTO atlas.tasks" not in s
assert "UPDATE atlas.task_release_queue_items" not in s
assert "DELETE FROM " not in s and "DROP TABLE" not in s and "CASCADE" not in s
assert s.count("BEGIN;")==1 and s.count("COMMIT;")==1
assert s.count("$source$")==2 and s.count("$function$")==4
# The EXISTING full-schema clone carrier will invoke this signed proof only
# after exact source admission and a disposable C1 fixture. A static CI pass
# here cannot substitute for PostgreSQL semantic compile or signed execution.
from pathlib import Path
import ast
package=Path(__file__).resolve().parents[1]/"candidates/atlas/atlas_legacy_queue_owner_canonical_work_cutover_v1"
fixture=(package/"clone_fixture.sql").read_text()
post=(package/"postconditions.sql").read_text()
signed_path=package/"validate_signed_queue_owner.py"
signed=signed_path.read_text()
ast.parse(signed,filename=str(signed_path))
assert "INSERT INTO atlas.tasks" in fixture and "INSERT INTO atlas.task_release_queue_items" in fixture
assert "UPDATE atlas.tasks" not in fixture and "DELETE FROM atlas" not in fixture
assert "e5200000-0000-4000-8000-000000000d24" in fixture
assert "noTaskMeansSeparateOriginalNeedReview" in s
assert "has_function_privilege('anon'" in post and "has_function_privilege('service_role'" in post
for marker in ("127[.]0[.]0[.]1","c1.sign_in(","\"worker\"","\"outsider\"","\"no-seat\"",
               "already_reviewed","p_expected_queue_updated_at","pg_advisory_xact_lock"):
    assert marker in (signed+s),marker
assert "INSERT INTO atlas.work_items" not in signed
assert "supabase.co" not in signed and "https://" not in signed
print("PASS held queue-to-existing-Work source and local signed-proof contract ONLY")
