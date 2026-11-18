-- U1.5: READ-ONLY live schema/source compatibility survey.
-- This file is SELECT-only. It does NOT restore, copy, export or alter data,
-- create an institutional root, grant a permission or operate on Accounts.
-- Report aggregate counts only; never enumerate real organizations/People.
WITH
 functions AS (
  SELECT
   to_regprocedure('atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)')
     IS NOT NULL AS atlas_governing_source_live,
   to_regprocedure('atlas.current_person_id_v1()')
     IS NOT NULL AS atlas_current_person_live,
   to_regprocedure('atlas.current_person_for_private_course_v1()')
     IS NOT NULL AS course_specific_person_live,
   to_regprocedure('reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)')
     IS NOT NULL AS reality_resolver_live,
   to_regclass('compatibility.legacy_bindings') IS NOT NULL AS explicit_org_identity_bridge_live
 ),
 active_governing AS (
  SELECT
   p.id,p.organization_id,p.ledger_id,
   nl.id IS NOT NULL AS native_ledger_exists,
   al.status='active' AS atlas_ledger_active,
   CASE WHEN al.status='active' AND nl.ledger_state='active'
       AND nl.retired_at IS NULL AND e.identity_state='canonical'
       AND e.entity_kind IN ('business','organization')
        THEN true ELSE false END AS canonical_native_ledger,
   m.mapping_count,
   m.same_count
  FROM atlas.ledger_organization_participations p
  JOIN atlas.organizations o ON o.id=p.organization_id AND o.status='active'
  LEFT JOIN atlas.ledgers al ON al.id=p.ledger_id
  LEFT JOIN ledger.ledgers nl ON nl.id=p.ledger_id
  LEFT JOIN reality.entities e ON e.id=nl.subject_entity_id
  LEFT JOIN LATERAL (
   SELECT count(*) AS mapping_count,
    count(*) FILTER (WHERE b.new_id=nl.subject_entity_id) AS same_count
   FROM compatibility.legacy_bindings b
   JOIN reality.entities entity ON entity.id=b.new_id
   WHERE b.legacy_schema='atlas' AND b.legacy_table='organizations'
    AND b.legacy_key=p.organization_id::text
    AND b.disposition='maps_to'
    AND b.new_schema='reality' AND b.new_table='entities'
    AND entity.identity_state='canonical'
    AND entity.entity_kind IN ('business','organization')
  ) m ON true
  WHERE p.status='active' AND p.ended_at IS NULL
   AND p.participation_kind='governing' AND p.is_compatibility_primary
 ),
 rollup AS (
  SELECT
   count(*) AS active_primary_org_ledger_pairs,
   count(*) FILTER (WHERE canonical_native_ledger) AS canonical_native_pairs,
   count(*) FILTER (WHERE canonical_native_ledger
       AND mapping_count=1 AND same_count=1) AS exact_unique_compatible,
   count(*) FILTER (WHERE mapping_count=0) AS missing_explicit_mapping,
   count(*) FILTER (WHERE mapping_count>1) AS ambiguous_explicit_mapping,
   count(*) FILTER (WHERE mapping_count=1 AND same_count=0) AS foreign_mapping,
   count(*) FILTER (WHERE NOT canonical_native_ledger) AS inactive_or_unresolved_native_ledger,
   count(*) FILTER (WHERE NOT native_ledger_exists) AS native_ledger_missing,
   count(*) FILTER (WHERE NOT native_ledger_exists AND mapping_count=0)
      AS both_native_ledger_and_mapping_missing,
   count(*) FILTER (WHERE NOT native_ledger_exists AND mapping_count>0)
      AS mapping_without_native_ledger,
   count(*) FILTER (WHERE native_ledger_exists AND mapping_count=0)
      AS native_ledger_without_mapping,
   count(*) FILTER (WHERE NOT atlas_ledger_active)
      AS governing_atlas_ledger_inactive
  FROM active_governing
 )
SELECT jsonb_build_object(
 'contractVersion','held_titus_u1_live_structure_readonly_v2',
 'sourceFunctions',to_jsonb(functions),
 'aggregateCounts',to_jsonb(rollup),
 'releaseApproved',false,
 'protectedProductionSchemaCloneVerified',false
) AS report
FROM functions CROSS JOIN rollup;
