#!/usr/bin/env python3
"""HELD, fictional-only legacy mowing Task/occurrence fixture for a future signed clone.

This is NOT a migration, production seed, owner action, historical cancellation,
or permission to run the already-consumed #2784 signed gate again. A separate
exact owner-controlled test is required before any signed acceptance claim.

Create ONE previously released legacy mowing Task with its released occurrence,
PLUS one separate still-planned occurrence in the original fictional mowing area.
Install BEFORE owner Rulebook adoption and worker U2/U4/P3 signed transitions,
not by bypassing the native guards after they have become effective. Keep the
frozen original P3 signed snapshot, historical companion and lifecycle authority.
All writes are to an exact disposable loopback PostgreSQL 'postgres' database.
"""
import json
import re
from collections.abc import Mapping

ORG = "e5200000-0000-4000-8000-000000000801"
FARM = "e5200000-0000-4000-8000-000000000b01"
STATE = "e5200000-0000-4000-8000-000000000d05"
DEFINITION = "e5300000-0000-4000-8000-000000000701"
POLICY = "e5300000-0000-4000-8000-000000000702"
RELEASED = "e5300000-0000-4000-8000-000000000703"
PLANNED = "e5300000-0000-4000-8000-000000000704"
TASK = "e5300000-0000-4000-8000-000000000705"
CONTRACT = "uni_ops_prior_mowing_carriers_disposable_v1"
LOCAL_DB = r"postgres(?:ql)?://postgres:[^@/]+@127[.]0[.]0[.]1:[0-9]{4,5}/postgres"

# This SQL is fixed literal source, not generated from live IDs or real rows.
# Explicit BEGIN/COMMIT makes the fictional carrier seed all-or-nothing.
INSTALL_SQL = f"""BEGIN;
DO $prior_mowing_preflight$
BEGIN
 IF current_database()<>'postgres'
    OR (SELECT count(*) FROM atlas.farms WHERE id='{FARM}'::uuid
         AND organization_id='{ORG}'::uuid)<>1
    OR (SELECT count(*) FROM atlas.rhythm_state WHERE id='{STATE}'::uuid
         AND organization_id='{ORG}'::uuid AND farm_id='{FARM}'::uuid
         AND rhythm_key='mowing')<>1
    OR EXISTS (SELECT 1 FROM atlas.governed_farm_rulebook_scope_versions_v1)
    OR EXISTS (SELECT 1 FROM atlas.governed_prework_candidate_offers_v1)
    OR EXISTS (SELECT 1 FROM atlas.work_definitions WHERE id='{DEFINITION}'::uuid)
    OR EXISTS (SELECT 1 FROM atlas.work_release_policies WHERE id='{POLICY}'::uuid)
    OR EXISTS (SELECT 1 FROM atlas.planned_work_occurrences
               WHERE id IN ('{RELEASED}'::uuid,'{PLANNED}'::uuid))
    OR EXISTS (SELECT 1 FROM atlas.tasks WHERE id='{TASK}'::uuid)
 THEN
   RAISE EXCEPTION 'Prior-mowing fixture requires clean prepolicy disposable source'
      USING ERRCODE='42501';
 END IF;
END
$prior_mowing_preflight$;
INSERT INTO atlas.work_definitions
  (id,farm_id,stable_key,title_template,task_type,source_kind,
   default_visibility_scope,metadata)
VALUES ('{DEFINITION}'::uuid,'{FARM}'::uuid,
 'clone:prior-mowing-definition','Fictional earlier mowing duty',
 'mowing','rhythm_state','system_internal',
 '{{"cloneFixture":true,"priorCarrier":true}}'::jsonb);
INSERT INTO atlas.work_release_policies
  (id,farm_id,work_definition_id,stable_key,gate_type,active,gate_config,metadata)
VALUES ('{POLICY}'::uuid,'{FARM}'::uuid,'{DEFINITION}'::uuid,
 'clone:prior-mowing-manual-release','manual',true,
 '{{"requiresExplicitHumanRelease":true}}'::jsonb,
 '{{"cloneFixture":true,"priorCarrier":true}}'::jsonb);
INSERT INTO atlas.planned_work_occurrences
  (id,farm_id,work_definition_id,release_policy_id,occurrence_key,
   source_kind,source_id,title,state,released_at,work_lane,metadata)
VALUES
 ('{RELEASED}'::uuid,'{FARM}'::uuid,'{DEFINITION}'::uuid,'{POLICY}'::uuid,
  'clone:prior-mowing-released','rhythm_state','{STATE}'::uuid,
  'Fictional old released mowing occurrence','released',
  now()-interval '3 days','rhythm',
  '{{"cloneFixture":true,"priorCarrier":true}}'::jsonb),
 ('{PLANNED}'::uuid,'{FARM}'::uuid,'{DEFINITION}'::uuid,'{POLICY}'::uuid,
  'clone:prior-mowing-planned','rhythm_state','{STATE}'::uuid,
  'Fictional old planned mowing occurrence','planned',
  NULL,'rhythm',
  '{{"cloneFixture":true,"priorCarrier":true}}'::jsonb);
INSERT INTO atlas.tasks
  (id,organization_id,farm_id,title,task_type,status,generated_from,
   generated_from_id,origin_kind,work_lane,visibility_scope,
   planned_occurrence_id,released_at,metadata)
VALUES ('{TASK}'::uuid,'{ORG}'::uuid,'{FARM}'::uuid,
 'Fictional old released mowing Task','mowing','open','rhythm_state',
 '{STATE}'::uuid,'generated','rhythm','system_internal',
 '{RELEASED}'::uuid,now()-interval '3 days',
 '{{"cloneFixture":true,"priorCarrier":true}}'::jsonb);
UPDATE atlas.planned_work_occurrences
 SET released_task_id='{TASK}'::uuid
 WHERE id='{RELEASED}'::uuid AND state='released'
   AND released_task_id IS NULL;
DO $prior_mowing_postcondition$
BEGIN
 IF (SELECT count(*) FROM atlas.tasks
      WHERE id='{TASK}'::uuid AND organization_id='{ORG}'::uuid
        AND farm_id='{FARM}'::uuid AND status='open'
        AND released_at IS NOT NULL
        AND planned_occurrence_id='{RELEASED}'::uuid)<>1
 OR (SELECT count(*) FROM atlas.planned_work_occurrences
      WHERE id='{RELEASED}'::uuid AND farm_id='{FARM}'::uuid
        AND state='released' AND released_task_id='{TASK}'::uuid)<>1
 OR (SELECT count(*) FROM atlas.planned_work_occurrences
      WHERE id='{PLANNED}'::uuid AND farm_id='{FARM}'::uuid
        AND state='planned' AND released_task_id IS NULL)<>1
 THEN
  RAISE EXCEPTION 'Prior-mowing fixture did not establish exact linked carriers'
    USING ERRCODE='23514';
 END IF;
END
$prior_mowing_postcondition$;
COMMIT;"""

# Returns precisely one JSON object from three specific fictional carrier IDs.
# No scan of real-world legacy rows, no issuer, no task update, no auth bypass.
SNAPSHOT_SQL = f"""SELECT jsonb_build_object(
 'contract','{CONTRACT}',
 'legacyTask',(
    SELECT to_jsonb(t) FROM atlas.tasks t WHERE t.id='{TASK}'::uuid
       AND t.organization_id='{ORG}'::uuid AND t.farm_id='{FARM}'::uuid),
 'releasedOccurrence',(
    SELECT to_jsonb(o) FROM atlas.planned_work_occurrences o
       WHERE o.id='{RELEASED}'::uuid AND o.farm_id='{FARM}'::uuid),
 'plannedOccurrence',(
    SELECT to_jsonb(o) FROM atlas.planned_work_occurrences o
       WHERE o.id='{PLANNED}'::uuid AND o.farm_id='{FARM}'::uuid)
)::text"""

# Fixture creation is NOT permission for old Task triggers to manufacture new
# canonical Work, Result, allocation, offer, plan or principal obligation.
# Read only total censuses before and after the synthetic carrier seed.
NONCARRIER_CENSUS_SQL = f"""SELECT jsonb_build_object(
 'work',(SELECT count(*) FROM atlas.work_items WHERE organization_id='{ORG}'::uuid),
 'allocations',(SELECT count(*) FROM atlas.work_allocations WHERE organization_id='{ORG}'::uuid),
 'offers',(SELECT count(*) FROM atlas.governed_prework_candidate_offers_v1
            WHERE organization_id='{ORG}'::uuid),
 'plans',(SELECT count(*) FROM atlas.work_execution_plans WHERE organization_id='{ORG}'::uuid),
 'results',(SELECT count(*) FROM atlas.work_execution_results WHERE organization_id='{ORG}'::uuid),
 'acceptances',(SELECT count(*) FROM atlas.work_result_acceptances
                WHERE organization_id='{ORG}'::uuid),
 'ownerObligations',(SELECT count(*) FROM atlas.owner_obligations)
)::text"""

class PriorMowingRefusal(AssertionError):
    """Safe constant error: never emit captured rows, SQL, or actor details."""

def _loopback(db_url):
    if not isinstance(db_url,str) or not re.fullmatch(LOCAL_DB,db_url):
        raise PriorMowingRefusal("Prior mowing requires disposable loopback PG17")

def _noncarrier_census(db_url,sql):
    try:
        raw=sql(db_url,NONCARRIER_CENSUS_SQL)
        if not isinstance(raw,str) or raw.count("\n")>1:
            raise ValueError("Not a single JSON census")
        data=json.loads(raw)
        if (not isinstance(data,dict)
            or set(data)!={"work","allocations","offers","plans","results",
                             "acceptances","ownerObligations"}
            or any(type(v) is not int or v<0 for v in data.values())):
            raise ValueError("Unrecognized noncarrier census")
        return data
    except Exception:
        raise PriorMowingRefusal("Fixture noncarrier census unavailable") from None

def install(db_url,sql):
    _loopback(db_url)
    if not callable(sql):
        raise PriorMowingRefusal("Exact isolated SQL carrier required")
    before=_noncarrier_census(db_url,sql)
    # Never echo SQL or PostgreSQL result; errors are redacted by caller.
    try:
        sql(db_url,INSTALL_SQL)
    except Exception:
        raise PriorMowingRefusal("Prior mowing physical seed refused") from None
    after=_noncarrier_census(db_url,sql)
    if before!=after:
        raise PriorMowingRefusal("Fixture manufactured additional native authority or Work")

def capture(db_url,sql):
    _loopback(db_url)
    if not callable(sql):
        raise PriorMowingRefusal("Exact isolated SQL reader required")
    raw=sql(db_url,SNAPSHOT_SQL)
    if not isinstance(raw,str) or not raw.strip().startswith("{") or raw.count("\n")>1:
        raise PriorMowingRefusal("Prior mowing snapshot was not unique")
    try:
        obj=json.loads(raw)
    except (ValueError,TypeError) as exc:
        raise PriorMowingRefusal("Prior mowing JSON was invalid") from None
    if not isinstance(obj,dict) or obj.get("contract")!=CONTRACT:
        raise PriorMowingRefusal("Prior mowing snapshot contract mismatch")
    return obj

def _require_prior_rows(record):
    if not isinstance(record,Mapping) or record.get("contract")!=CONTRACT:
        raise PriorMowingRefusal("Prior mowing evidence missing")
    task=record.get("legacyTask")
    released=record.get("releasedOccurrence")
    planned=record.get("plannedOccurrence")
    if not all(isinstance(x,Mapping) for x in (task,released,planned)):
        raise PriorMowingRefusal("Nonempty physical legacy Task and occurrences required")
    if not (
        task.get("id")==TASK and task.get("organization_id")==ORG
        and task.get("farm_id")==FARM and task.get("status")=="open"
        and task.get("work_lane")=="rhythm"
        and task.get("planned_occurrence_id")==RELEASED
        and task.get("released_at") is not None
        and task.get("generated_from_id")==STATE
        and released.get("id")==RELEASED and released.get("farm_id")==FARM
        and released.get("source_id")==STATE
        and released.get("state")=="released"
        and released.get("released_task_id")==TASK
        and released.get("released_at") is not None
        and planned.get("id")==PLANNED and planned.get("farm_id")==FARM
        and planned.get("source_id")==STATE
        and planned.get("state")=="planned"
        and planned.get("released_task_id") is None
        and planned.get("released_at") is None
    ):
        raise PriorMowingRefusal("Prior mowing physical identity/state relationship failed")
    return True

def require_preserved(before,after,p3_before,p3_after):
    """Preserve entire known old rows AND source-owned P3 census/identity sets."""
    _require_prior_rows(before)
    _require_prior_rows(after)
    for key in ("legacyTask","releasedOccurrence","plannedOccurrence"):
        if before[key]!=after[key]:
            raise PriorMowingRefusal("Historical retirement altered prior mowing carrier row")
    for snap in (p3_before,p3_after):
        if not isinstance(snap,Mapping) or (
            snap.get("contract")!="uni_ops_p3_signed_result_snapshot_v1"
            or snap.get("phase")!="replay"
            or type(snap.get("legacyTaskTotal")) is not int
            or type(snap.get("plannedOccurrenceTotal")) is not int
            or snap["legacyTaskTotal"]<1 or snap["plannedOccurrenceTotal"]<2
            or not isinstance(snap.get("legacyReleasedTaskIds"),list)
            or TASK not in snap["legacyReleasedTaskIds"]
            or not isinstance(snap.get("eligibleOrReleasedOccurrenceIds"),list)
            or RELEASED not in snap["eligibleOrReleasedOccurrenceIds"]
            or not isinstance(snap.get("releasedOccurrenceIds"),list)
            or RELEASED not in snap["releasedOccurrenceIds"])):
            raise PriorMowingRefusal("P3 never observed nonempty old mowing carriers")
    for key in ("legacyTaskTotal","plannedOccurrenceTotal",
                "legacyReleasedTaskIds","eligibleOrReleasedOccurrenceIds",
                "releasedOccurrenceIds"):
        if p3_before[key]!=p3_after[key]:
            raise PriorMowingRefusal("Historical retirement changed P3 old carrier census")
    return True
