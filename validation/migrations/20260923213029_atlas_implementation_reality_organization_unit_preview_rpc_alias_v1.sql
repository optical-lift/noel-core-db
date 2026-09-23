begin;

do $validation$
declare
  v_alias regprocedure;
  v_def text;
begin
  v_alias:=to_regprocedure(
    'public.preview_implementation_reality_org_unit_promotion_self_api_v1(uuid)'
  );

  if v_alias is null then
    raise exception 'PostgREST-safe Organization Unit preview RPC alias is missing.';
  end if;

  if length('preview_implementation_reality_org_unit_promotion_self_api_v1')>63 then
    raise exception 'Organization Unit preview alias exceeds PostgreSQL identifier limit.';
  end if;

  if not has_function_privilege('authenticated',v_alias,'EXECUTE') then
    raise exception 'Authenticated role cannot execute Organization Unit preview alias.';
  end if;

  if has_function_privilege('anon',v_alias,'EXECUTE')
     or has_function_privilege('service_role',v_alias,'EXECUTE') then
    raise exception 'Organization Unit preview alias leaked outside authenticated membrane.';
  end if;

  select lower(pg_get_functiondef(v_alias))
  into v_def;

  if v_def not like '%preview_implementation_reality_organization_unit_promotion_self%'
     or v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Organization Unit preview alias does not remain a read-only wrapper.';
  end if;
end;
$validation$;

rollback;
