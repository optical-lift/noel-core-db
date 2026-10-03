select
  atlas.personal_atlas_compatibility_principal_id_v1(
    (select id from reality.entities where stable_key='lex')
  ) as lex_compatibility_principal_id;

select
  pg_get_functiondef('atlas.personal_capacity_policies_self_api_v1()'::regprocedure)
    not ilike '%current_principal_id_v1%' as capacity_read_no_current_principal,
  pg_get_functiondef('atlas.personal_capacity_policies_self_api_v1()'::regprocedure)
    not ilike '%organization_memberships%' as capacity_read_no_org_membership,
  pg_get_functiondef('atlas.personal_set_capacity_policy_self_api_v1(jsonb)'::regprocedure)
    not ilike '%current_principal_id_v1%' as capacity_write_no_current_principal,
  pg_get_functiondef('atlas.personal_set_capacity_policy_self_api_v1(jsonb)'::regprocedure)
    not ilike '%organization_memberships%' as capacity_write_no_org_membership,
  pg_get_functiondef('atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure)
    not ilike '%current_principal_id_v1%' as household_write_no_current_principal,
  pg_get_functiondef('atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure)
    not ilike '%organization_memberships%' as household_write_no_org_membership;

select n.nspname as schema_name,p.proname,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'personal_atlas_compatibility_principal_id_v1',
    'personal_capacity_policies_self_api_v1',
    'personal_set_capacity_policy_self_api_v1',
    'personal_upsert_household_rhythm_local_self_api_v1'
  )
order by p.proname;
