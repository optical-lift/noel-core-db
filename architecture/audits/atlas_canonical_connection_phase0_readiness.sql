-- ATLAS canonical Connection kernel phase 0: aggregated readiness ONLY.
-- Source: ledger.seats, ledger.ledgers, ledger.connections,
--         reality.entities, reality.relationship_kinds, reality.entity_relationships.
-- Does not SELECT names, UUIDs, original testimony or private basis/evidence;
-- no writes, DDL, grant or user-access broadening.
WITH
ledger_counts AS (
  SELECT count(*)::bigint AS ledgers,
         count(distinct subject_entity_id)::bigint AS distinct_business_subjects
  FROM ledger.ledgers
),
seat_counts AS (
  SELECT count(*)::bigint AS seats,
         count(distinct (person_entity_id,ledger_id))::bigint AS distinct_person_ledger_pairs,
         count(*) FILTER (WHERE seat_state='active')::bigint AS active_seats
  FROM ledger.seats
),
collision_groups AS (
  SELECT count(*)::bigint AS ambiguous_person_business_groups
  FROM (
    SELECT s.person_entity_id,l.subject_entity_id
    FROM ledger.seats s
    JOIN ledger.ledgers l ON l.id=s.ledger_id
    GROUP BY s.person_entity_id,l.subject_entity_id
    HAVING count(DISTINCT s.ledger_id)>1
  ) groups_violating_lossy_business_mapping
),
ledger_relation_counts AS (
  SELECT count(*)::bigint AS ledger_to_ledger_connections
  FROM ledger.connections
),
reality_counts AS (
  SELECT count(*)::bigint AS reality_relationships
  FROM reality.entity_relationships
),
missing_person_ledger_kind AS (
  SELECT count(*)::bigint AS registered_person_ledger_kinds
  FROM reality.relationship_kinds
  WHERE kind_state='active'
    AND 'person'=ANY(allowed_subject_kinds)
    AND 'ledger_context'=ANY(allowed_object_kinds)
),
missing_ledger_context_entities AS (
  SELECT count(*)::bigint AS canonical_ledger_context_entities
  FROM reality.entities
  WHERE entity_kind='ledger_context' AND identity_state='canonical'
)
SELECT jsonb_build_object(
  'contract','atlas_canonical_connection_readiness_v1',
  'ledgerCount',(SELECT ledgers FROM ledger_counts),
  'distinctLedgerOwningBusinessEntities',(SELECT distinct_business_subjects FROM ledger_counts),
  'nativeSeatCount',(SELECT seats FROM seat_counts),
  'distinctPersonLedgerSeatPairs',(SELECT distinct_person_ledger_pairs FROM seat_counts),
  'activeNativeSeats',(SELECT active_seats FROM seat_counts),
  'personBusinessCollapseCollisionGroups',(SELECT ambiguous_person_business_groups FROM collision_groups),
  'ledgerToLedgerRows',(SELECT ledger_to_ledger_connections FROM ledger_relation_counts),
  'existingRealityRelationships',(SELECT reality_relationships FROM reality_counts),
  'registeredPersonLedgerContextKinds',(SELECT registered_person_ledger_kinds FROM missing_person_ledger_kind),
  'canonicalLedgerContextEntities',(SELECT canonical_ledger_context_entities FROM missing_ledger_context_entities),
  'autoPromotionAuthorized',false,
  'recordAccessGranted',false
) AS readiness;
