-- Lex + Elm Reality / Ledger cutover acceptance v1.

select
  e.id,
  e.stable_key,
  e.entity_kind,
  e.display_name,
  e.identity_state,
  e.metadata->>'admissionState' as admission_state
from reality.entities e
where e.id in (
  '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
  'de584041-a636-424d-b8f5-2ff90ba3685e'::uuid
)
order by e.display_name;

select
  pa.id as personal_atlas_id,
  e.id as person_entity_id,
  e.display_name,
  b.auth_user_id,
  b.binding_state,
  pa.atlas_state,
  pa.native
from personal.atlases pa
join reality.entities e on e.id=pa.person_entity_id
join reality.auth_person_bindings b
  on b.person_entity_id=e.id and b.binding_state='active'
where e.id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid;

select
  l.id,
  l.stable_key,
  l.name,
  l.subject_entity_id,
  e.display_name as subject,
  c.case_kind,
  c.onboarding_state,
  c.practitioner_person_entity_id
from ledger.ledgers l
join reality.entities e on e.id=l.subject_entity_id
join ledger.onboarding_cases c on c.id=l.onboarding_case_id
where l.id in (
  '0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid,
  '8df18008-28ef-48e9-babd-1eb0e0dd7e3c'::uuid
)
order by l.stable_key;

select
  s.id as seat_id,
  l.stable_key as ledger_key,
  e.display_name as person_name,
  s.seat_state,
  s.seat_basis->>'meaning' as meaning,
  (s.seat_basis->>'doesNotEstablishOwnership')::boolean as does_not_establish_ownership,
  (s.seat_basis->>'doesNotPreservePrincipalAuthority')::boolean as does_not_preserve_principal_authority
from ledger.seats s
join ledger.ledgers l on l.id=s.ledger_id
join reality.entities e on e.id=s.person_entity_id
where e.id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid
order by l.stable_key;

select
  (select count(*) from atlas.organization_ledger_entries
   where ledger_id='0c5f53dd-3659-4fed-b8d7-a771a4172f36') as legacy_flower_entries,
  (select count(*) from ledger.actions
   where ledger_id='0c5f53dd-3659-4fed-b8d7-a771a4172f36') as new_flower_actions,
  (select count(*) from atlas.organization_ledger_entries
   where ledger_id='8df18008-28ef-48e9-babd-1eb0e0dd7e3c') as legacy_venue_entries,
  (select count(*) from ledger.actions
   where ledger_id='8df18008-28ef-48e9-babd-1eb0e0dd7e3c') as new_venue_actions;

select
  count(*) as forbidden_identity_authority_columns
from information_schema.columns
where table_schema in ('reality','personal','ledger')
  and (
    column_name ilike '%principal%'
    or column_name ilike '%organization%'
    or column_name ilike '%membership%'
    or column_name in ('owner_user_id','role')
  );

select
  count(*) filter(where legacy_table='principals' and disposition='retired') as retired_principals,
  count(*) filter(where legacy_table='principal_ledger_authorities' and disposition='retired') as retired_principal_ledger_authorities,
  count(*) filter(where legacy_table='ledger_organization_participations' and disposition='retired') as retired_organization_participations,
  count(*) filter(where legacy_table='ledger_relationships' and disposition='retired') as retired_legacy_ledger_relationships
from compatibility.legacy_bindings;

select
  (select count(*) from ledger.connections) as new_ledger_connections,
  (select count(*) from ledger.exposures) as new_ledger_exposures;
