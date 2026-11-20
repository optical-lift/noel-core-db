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
assert "INSERT INTO atlas.work_items" not in s
assert "INSERT INTO atlas.tasks" not in s
assert "UPDATE atlas.task_release_queue_items" not in s
assert "DELETE FROM " not in s and "DROP TABLE" not in s and "CASCADE" not in s
assert s.count("BEGIN;")==1 and s.count("COMMIT;")==1
for marker in ("$source$","$read$","$decide$"): assert s.count(marker)==2
print("PASS held queue-to-existing-Work owner reconciliation source contract ONLY")
