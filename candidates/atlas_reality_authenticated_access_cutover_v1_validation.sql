-- Atlas Reality authenticated access cutover v1 validation

select
  pg_get_functiondef('atlas.current_person_id_v1()'::regprocedure) not ilike '%person_auth_credentials%' as current_person_uses_reality_binding,
  pg_get_functiondef('atlas.reality_access_self_api_v1()'::regprocedure) not ilike '%organization_memberships%' as reality_access_avoids_organization_memberships,
  pg_get_functiondef('atlas.reality_access_self_api_v1()'::regprocedure) not ilike '%principal_ledger_authorities%' as reality_access_avoids_principal_ledger_authority,
  pg_get_functiondef('atlas.principal_ledgers_self_api_v1()'::regprocedure) not ilike '%principal_ledger_authorities%' as ledger_read_uses_seats,
  pg_get_functiondef('atlas.principal_self_context_api_v1()'::regprocedure) not ilike '%principal_ledger_authorities%' as principal_read_avoids_principal_ledger_authority,
  pg_get_functiondef('atlas.current_session_context_api_v2()'::regprocedure) not ilike '%organization_memberships%' as session_v2_avoids_organization_memberships;

select
  count(*) filter (where e.id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e') as lex_reality_person_count,
  count(*) filter (where e.id='de584041-a636-424d-b8f5-2ff90ba3685e') as elm_reality_entity_count
from reality.entities e;

select
  count(*) as lex_native_personal_atlas_count
from personal.atlases a
where a.person_entity_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'
  and a.native
  and a.atlas_state='active';

select
  count(*) as lex_active_elm_seat_count
from ledger.seats s
where s.person_entity_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'
  and s.seat_state='active'
  and s.ended_at is null
  and s.ledger_id in (
    '0c5f53dd-3659-4fed-b8d7-a771a4172f36',
    '8df18008-28ef-48e9-babd-1eb0e0dd7e3c'
  );

select
  p.proname,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'reality_access_self_api_v1',
    'current_session_context_api_v2',
    'principal_ledgers_self_api_v1',
    'principal_self_context_api_v1'
  )
order by p.proname;
