select
  (select count(*) from atlas.company_work_participation_offers) as live_offer_count,
  (select count(*) from atlas.work_allocations
    where allocation_role in ('participant','approver') and state='active') as active_collaboration_count;

select
  has_table_privilege('anon','atlas.company_work_participation_offers','SELECT') as anon_select,
  has_table_privilege('authenticated','atlas.company_work_participation_offers','SELECT') as authenticated_select,
  has_table_privilege('service_role','atlas.company_work_participation_offers','SELECT') as service_select;

select p.oid::regprocedure::text as signature,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute,
       p.prosecdef as security_definer
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'offer_company_work_participation_self_api_v1',
    'company_work_participation_offers_self_api_v1',
    'respond_company_work_participation_offer_self_api_v1',
    'withdraw_company_work_participation_offer_self_api_v1'
  )
order by p.proname;

select
  pg_get_functiondef(
    'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)'::regprocedure
  ) ilike '%offer_company_work_participation_self_api_v1%' as adapter_uses_generic_offer,
  pg_get_functiondef(
    'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)'::regprocedure
  ) ilike '%view the source endpoint%' as adapter_preserves_source_visibility,
  pg_get_functiondef(
    'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)'::regprocedure
  ) not ilike '%insert into atlas.work_allocations%' as adapter_does_not_allocate_directly;
