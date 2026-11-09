-- Read-only exact source rule evidence for universal continuing-Work farm adapters.
-- No legacy tasks, user IDs, private text, grants, Work, observations or changes.
-- An observed rule proves only what the SOURCE permits as a qualifying result,
-- not that a place presently needs work or that a Person is authorized.
WITH source_rules AS (
  SELECT DISTINCT r.id, r.rhythm_key, r.qualifying_touches
  FROM atlas.rhythm_state s
  JOIN atlas.rhythm_rules r ON r.id=s.rhythm_rule_id
  JOIN atlas.rhythm_bindings b ON b.id=s.rhythm_binding_id
  WHERE r.status='active' AND b.active
    AND s.rhythm_key IN ('weed_stewardship','mowing')
), required_events(rhythm_key,actual_kind,effect,source_kind,source_event,partial_marker) AS (
  VALUES
    ('mowing','mowed_full','full','mowing_result','mowed_full',NULL::text),
    ('mowing','mowed_partial','partial','mowing_result','mowed_partial',NULL::text),
    ('mowing','acceptable_no_cut','conditional','mowing_result','acceptable_no_cut',NULL::text),
    ('weed_stewardship','weeded_full','full','object','weeded_reset',NULL::text),
    ('weed_stewardship','weeded_partial','partial','object','weeded','partial'),
    ('weed_stewardship','inspection_acceptable','conditional','field_log',
      'action:weed_inspection_acceptable',NULL::text)
), policies AS (
  SELECT r.rhythm_key,e.actual_kind, count(*) AS checked_rules,
    count(*) FILTER(WHERE EXISTS (
      SELECT 1 FROM jsonb_array_elements(r.qualifying_touches) AS touch(v)
      WHERE touch.v->>'effect'=e.effect
        AND touch.v->>'sourceKind'=e.source_kind
        AND (
          touch.v->>'sourceEvent'=e.source_event
          OR touch.v->'sourceEvents' ? e.source_event
        )
        AND (e.partial_marker IS NULL
          OR touch.v#>>'{payloadContains,metadata,transition}'=e.partial_marker)
    )) matched_rules
  FROM source_rules r
  JOIN required_events e ON e.rhythm_key=r.rhythm_key
  GROUP BY r.rhythm_key,e.actual_kind
)
SELECT rhythm_key,actual_kind,checked_rules,matched_rules,
  CASE WHEN checked_rules=matched_rules THEN 'SOURCE_RULE_MATCH'
       ELSE 'SOURCE_RULE_GAP' END finding
FROM policies
ORDER BY rhythm_key,actual_kind;
