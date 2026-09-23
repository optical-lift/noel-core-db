begin;

do $validation$
declare
  v_practitioner constant uuid:='f4700000-0000-4000-8000-000000000001'::uuid;
  v_ready constant uuid:='f4700000-0000-4000-8000-000000000301'::uuid;
  v_missing constant uuid:='f4700000-0000-4000-8000-000000000302'::uuid;
  v_duplicate constant uuid:='f4700000-0000-4000-8000-000000000303'::uuid;
  v_outside constant uuid:='f4700000-0000-4000-8000-000000000304'::uuid;
  v_technical constant uuid:='f4700000-0000-4000-8000-000000000305'::uuid;
  v_result jsonb;
  v_before jsonb;
  v_after jsonb;
  v_def text;
begin
  if to_regprocedure(
    'public.preview_implementation_reality_responsibility_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Responsibility preview membrane is missing.';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_responsibility_self_api_v1(uuid)'
  ) is not null then
    raise exception 'Read-only Responsibility preview unexpectedly contains mutation command.';
  end if;

  if length('preview_implementation_reality_responsibility_self_api_v1')>63 then
    raise exception 'Responsibility preview RPC exceeds PostgreSQL identifier limit.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select jsonb_agg(to_jsonb(r) order by r.id)
  into v_before
  from atlas.organization_responsibilities r;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_ready);
  if v_result->>'state'<>'ready'
     or not coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or v_result->'consequence'->>'responsibilityKind'<>'stewardship' then
    raise exception 'Valid Responsibility candidate was not read-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_missing);
  if v_result->>'state'<>'semantic_payload_required'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Missing responsibilityKind became ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_duplicate);
  if v_result->>'state'<>'canonical_identity_exists'
     or v_result->>'existingResponsibilityId'<>'f4700000-0000-4000-8000-000000000211' then
    raise exception 'Existing Responsibility was not recognized: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_outside);
  if v_result->>'state'<>'outside_implementation_scope'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Out-of-scope Responsibility became ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_technical);
  if v_result->>'state'<>'technical_identifier_not_allowed' then
    raise exception 'Responsibility stable key became authorable: %',v_result;
  end if;

  select jsonb_agg(to_jsonb(r) order by r.id)
  into v_after
  from atlas.organization_responsibilities r;

  if v_after is distinct from v_before then
    raise exception 'Responsibility preview mutated canonical truth.';
  end if;

  create function public.promote_implementation_reality_responsibility_self_api_v1(
    p_candidate_id uuid
  )
  returns jsonb
  language sql
  as $$ select jsonb_build_object('ok',true) $$;

  revoke all on function public.promote_implementation_reality_responsibility_self_api_v1(uuid)
    from public,anon,authenticated,service_role;
  grant execute on function public.promote_implementation_reality_responsibility_self_api_v1(uuid)
    to authenticated;

  v_result:=public.preview_implementation_reality_responsibility_self_api_v1(v_ready);
  if not coalesce((v_result->>'promotionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'canExecutePromotion')::boolean,false) then
    raise exception 'Responsibility preview did not activate exact command capability: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.preview_implementation_reality_responsibility_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.preview_implementation_reality_responsibility_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Responsibility preview leaked around public membrane.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.preview_implementation_reality_responsibility_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%establish_organization_responsibility%' then
    raise exception 'Internal Responsibility preview contains mutation authority.';
  end if;
end;
$validation$;

rollback;
