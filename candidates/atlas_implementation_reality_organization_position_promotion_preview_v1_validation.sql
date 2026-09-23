begin;

do $validation$
declare
  v_practitioner constant uuid:='f4600000-0000-4000-8000-000000000001'::uuid;
  v_ready constant uuid:='f4600000-0000-4000-8000-000000000301'::uuid;
  v_missing_kind constant uuid:='f4600000-0000-4000-8000-000000000302'::uuid;
  v_duplicate constant uuid:='f4600000-0000-4000-8000-000000000303'::uuid;
  v_unresolved_unit constant uuid:='f4600000-0000-4000-8000-000000000304'::uuid;
  v_outside constant uuid:='f4600000-0000-4000-8000-000000000305'::uuid;
  v_technical constant uuid:='f4600000-0000-4000-8000-000000000306'::uuid;
  v_result jsonb;
  v_before_positions jsonb;
  v_after_positions jsonb;
  v_before_candidates jsonb;
  v_after_candidates jsonb;
  v_def text;
begin
  if to_regprocedure(
    'public.preview_implementation_reality_position_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Position promotion preview membrane is missing.';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_position_self_api_v1(uuid)'
  ) is not null then
    raise exception 'Read-only Position preview unexpectedly contains mutation command.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  -- Fixture DML runs before candidate migration. Convert the currently lawful
  -- object=Organization placeholders after grammar is corrected to object=Unit.
  update atlas.implementation_reality_candidates
  set object_binding=case id
    when v_unresolved_unit then jsonb_build_object(
      'kind','organization_unit','label','Unknown Unit','resolution','unresolved'
    )
    when v_outside then jsonb_build_object(
      'kind','organization_unit','label','Outside Operations','resolution','canonical',
      'canonicalId','f4600000-0000-4000-8000-000000000212'
    )
    else jsonb_build_object(
      'kind','organization_unit','label','Operations','resolution','canonical',
      'canonicalId','f4600000-0000-4000-8000-000000000211'
    )
  end
  where id in (
    v_ready,v_missing_kind,v_duplicate,v_unresolved_unit,v_outside,v_technical
  );

  select jsonb_agg(to_jsonb(p) order by p.id)
  into v_before_positions
  from atlas.organization_positions p;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_before_candidates
  from atlas.implementation_reality_candidates c;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_ready);
  if v_result->>'state'<>'ready'
     or not coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true)
     or v_result->'consequence'->>'kind'<>'organization_position'
     or v_result->'consequence'->>'positionKind'<>'operations'
     or v_result->'consequence'->>'organizationUnitId'<>'f4600000-0000-4000-8000-000000000211' then
    raise exception 'Valid Position candidate was not read-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_missing_kind);
  if v_result->>'state'<>'semantic_payload_required'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Missing positionKind became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_duplicate);
  if v_result->>'state'<>'canonical_identity_exists'
     or v_result->>'existingPositionId'<>'f4600000-0000-4000-8000-000000000221'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Existing Position identity was silently duplicated: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_unresolved_unit);
  if v_result->>'state'<>'identity_resolution_required'
     or v_result->>'slot'<>'object'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Unresolved Unit became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_outside);
  if v_result->>'state'<>'outside_implementation_scope'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Out-of-scope Unit became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_technical);
  if v_result->>'state'<>'technical_identifier_not_allowed'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Technical stable key became Position authoring input: %',v_result;
  end if;

  select jsonb_agg(to_jsonb(p) order by p.id)
  into v_after_positions
  from atlas.organization_positions p;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_after_candidates
  from atlas.implementation_reality_candidates c;

  if v_after_positions is distinct from v_before_positions
     or v_after_candidates is distinct from v_before_candidates then
    raise exception 'Position promotion preview mutated canonical or candidate state.';
  end if;

  create function public.promote_implementation_reality_position_self_api_v1(
    p_candidate_id uuid
  )
  returns jsonb
  language sql
  as $$
    select jsonb_build_object('ok',true)
  $$;

  revoke all on function public.promote_implementation_reality_position_self_api_v1(uuid)
    from public,anon,authenticated,service_role;
  grant execute on function public.promote_implementation_reality_position_self_api_v1(uuid)
    to authenticated;

  v_result:=public.preview_implementation_reality_position_promotion_self_api_v1(v_ready);
  if not coalesce((v_result->>'canPromote')::boolean,false)
     or not coalesce((v_result->>'promotionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'canExecutePromotion')::boolean,false) then
    raise exception 'Position preview did not self-activate after exact promotion membrane became executable: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.preview_implementation_reality_position_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.preview_implementation_reality_position_promotion_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Position preview leaked around public practitioner membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.preview_implementation_reality_position_promotion_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Position preview.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.preview_implementation_reality_position_promotion_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%establish_organization_position%' then
    raise exception 'Internal Position preview contains mutation authority.';
  end if;
end;
$validation$;

rollback;
