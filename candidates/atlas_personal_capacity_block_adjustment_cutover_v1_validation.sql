select
  pg_get_functiondef('atlas.principal_capacity_policies_self_api_v1()'::regprocedure)
    not ilike '%current_principal_id_v1%' as old_policy_read_is_alias,
  pg_get_functiondef('atlas.principal_set_capacity_policy_api_v1(jsonb)'::regprocedure)
    not ilike '%current_principal_id_v1%' as old_policy_write_is_alias,
  pg_get_functiondef('atlas.principal_capacity_blocks_self_api_v1(timestamp with time zone,timestamp with time zone,boolean)'::regprocedure)
    not ilike '%current_principal_id_v1%' as old_block_read_is_alias,
  pg_get_functiondef('atlas.record_principal_capacity_block_self_api_v1(jsonb)'::regprocedure)
    not ilike '%current_principal_id_v1%' as old_block_write_is_alias,
  pg_get_functiondef('atlas.record_personal_capacity_block_self_api_v1(jsonb)'::regprocedure)
    ilike '%scope_id=v_person_id%' as block_evidence_uses_reality_person,
  pg_get_functiondef('atlas.record_personal_capacity_adjustment_self_api_v1(jsonb)'::regprocedure)
    ilike '%scope_id=v_person_id%' as adjustment_evidence_uses_reality_person;

select p.proname,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'personal_capacity_blocks_self_api_v1',
    'personal_capacity_adjustments_self_api_v1',
    'record_personal_capacity_block_self_api_v1',
    'record_personal_capacity_adjustment_self_api_v1',
    'transition_personal_capacity_block_self_api_v1',
    'transition_personal_capacity_adjustment_self_api_v1'
  )
order by p.proname;
