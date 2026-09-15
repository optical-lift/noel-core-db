begin;

do $$
begin
  if to_regprocedure('atlas.organization_company_work_positions_api_v1(uuid)') is null then raise exception 'Missing internal Position catalog.'; end if;
  if to_regprocedure('public.organization_company_work_positions_api_v1(uuid)') is null then raise exception 'Missing browser Position catalog.'; end if;
  if has_function_privilege('authenticated','atlas.organization_company_work_positions_api_v1(uuid)','execute') then raise exception 'Internal Position catalog leaked from atlas schema.'; end if;
  if has_function_privilege('anon','public.organization_company_work_positions_api_v1(uuid)','execute') then raise exception 'Anon can read governed Position catalog.'; end if;
  if not has_function_privilege('authenticated','public.organization_company_work_positions_api_v1(uuid)','execute') then raise exception 'Authenticated management caller cannot reach Position catalog.'; end if;
end;
$$;

rollback;
