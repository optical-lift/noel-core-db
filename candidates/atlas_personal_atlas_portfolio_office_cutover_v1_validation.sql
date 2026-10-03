select
  pg_get_functiondef(
    'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
  ) not ilike '%current_principal_id_v1%' as no_current_principal,
  pg_get_functiondef(
    'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
  ) not ilike '%organization_memberships%' as no_org_membership,
  pg_get_functiondef(
    'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
  ) not ilike '%is_farm_owner%' as no_farm_owner;

select p.proname,
       has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='atlas'
  and p.proname in (
    'personal_portfolio_office_author_self_api_v1',
    'principal_upsert_owner_obligation_api_v1',
    'principal_upsert_portfolio_thesis_api_v1',
    'principal_upsert_attention_policy_api_v1',
    'principal_upsert_operating_function_api_v1',
    'principal_upsert_great_game_scorecard_api_v1',
    'principal_upsert_capital_request_api_v1',
    'principal_upsert_investment_opportunity_api_v1'
  )
order by p.proname;
