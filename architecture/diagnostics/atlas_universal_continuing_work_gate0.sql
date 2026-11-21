-- Atlas Proper / universal continuing Work Gate 0.
-- READ-ONLY manual diagnostic; no grants, writes, private identifiers or signed impersonation.
-- Findings named GAP are honest failures, not permission to release tasks.
WITH org_work AS (
 SELECT count(*) AS n FROM atlas.work_items WHERE organization_id IS NOT NULL
), hh_work AS (
 SELECT count(*) AS n FROM atlas.work_items WHERE household_id IS NOT NULL
), subjects AS (
 SELECT count(*) FILTER (WHERE subject_domain='spatial') AS spatial,
        count(*) FILTER (WHERE subject_domain='household') AS household,
        count(*) FILTER (WHERE subject_domain='temporal') AS temporal
 FROM atlas.work_item_context_links
), farm AS (
 SELECT count(*) FILTER (WHERE rhythm_key='weed_stewardship') AS weed,
        count(*) FILTER (WHERE rhythm_key='mowing') AS mow
 FROM atlas.rhythm_state
), current_original AS (
 SELECT count(distinct s.id) AS n
 FROM atlas.rhythm_state s
 JOIN atlas.work_items w ON w.organization_id=s.organization_id
   AND w.source_object_type='planned_work_occurrence'
   AND w.source_object_id=s.current_occurrence_id AND w.work_state='open'
 WHERE s.rhythm_key IN ('weed_stewardship','mowing')
), hh AS (
 SELECT count(*) AS n FROM atlas.household_rhythms WHERE active
), result_source AS (
 SELECT (SELECT count(*) FROM atlas.rhythm_satisfactions) AS farm,
        (SELECT count(*) FROM atlas.care_result_events WHERE scope_kind='household') AS household
), mow_state AS (
 SELECT count(*) AS total,
        count(*) FILTER (WHERE m.status='resting') AS resting,
        count(*) FILTER (WHERE m.last_observed_at < now()-interval '30 days') AS stale
 FROM atlas.rhythm_state s
 LEFT JOIN atlas.mowing_area_state m ON m.object_id=s.subject_id
 WHERE s.rhythm_key='mowing'
)
SELECT 'original_work_organization' AS check_key,n::text AS observed,
       CASE WHEN n>0 THEN 'FOUND' ELSE 'GAP' END AS finding
FROM org_work
UNION ALL
SELECT 'original_work_household',n::text,
       CASE WHEN n>0 THEN 'FOUND' ELSE 'GAP' END
FROM hh_work
UNION ALL
SELECT 'subject_links',format('spatial=%s household=%s temporal=%s',spatial,household,temporal),
       CASE WHEN spatial>0 AND household>0 THEN 'FOUND' ELSE 'GAP' END
FROM subjects
UNION ALL
SELECT 'farm_rhythm_definitions',format('weed=%s mow=%s',weed,mow),
       CASE WHEN weed>0 AND mow>0 THEN 'FOUND' ELSE 'GAP' END
FROM farm
UNION ALL
SELECT 'farm_rhythm_open_original_work',n::text,
       CASE WHEN n>0 THEN 'PARTIAL_NOT_SIGNED' ELSE 'GAP' END
FROM current_original
UNION ALL
SELECT 'active_household_rhythms',n::text,
       CASE WHEN n>0 THEN 'FOUND' ELSE 'GAP' END
FROM hh
UNION ALL
SELECT 'result_sources',format('farm=%s household=%s',farm,household),
       'NOT_END_TO_END_PROOF'
FROM result_source
UNION ALL
SELECT 'mow_stale_or_resting',format('total=%s resting=%s stale=%s',total,resting,stale),
       'REASSESS_PHYSICAL_NEED'
FROM mow_state
ORDER BY check_key;