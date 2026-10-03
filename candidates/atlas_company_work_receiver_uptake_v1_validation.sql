select relrowsecurity,relforcerowsecurity
from pg_class
where oid='atlas.company_work_responsibility_transfer_offers'::regclass;

select
  has_table_privilege('anon','atlas.company_work_responsibility_transfer_offers','SELECT') as anon_select,
  has_table_privilege('authenticated','atlas.company_work_responsibility_transfer_offers','SELECT') as authenticated_select,
  has_table_privilege('service_role','atlas.company_work_responsibility_transfer_offers','SELECT') as service_select;

select p.oid::regprocedure::text as signature,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') as service_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'offer_company_work_responsibility_transfer_self_api_v1',
    'company_work_responsibility_transfer_offers_self_api_v1',
    'respond_company_work_responsibility_transfer_offer_self_api_v1',
    'withdraw_company_work_responsibility_transfer_offer_self_api_v1'
  )
order by p.proname;

select pg_get_functiondef(
  'atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)'::regprocedure
) not ilike '%communication_endpoint_membership_has_capability_v1%' as handoff_no_endpoint_authority;
