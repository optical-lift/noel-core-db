begin;

do $validation$
declare
  v_practitioner constant uuid:='f4400000-0000-4000-8000-000000000001'::uuid;
  v_ready constant uuid:='f4400000-0000-4000-8000-000000000301'::uuid;
  v_nested constant uuid:='f4400000-0000-4000-8000-000000000302'::uuid;
  v_missing_kind constant uuid:='f4400000-0000-4000-8000-000000000303'::uuid;
  v_duplicate constant uuid:='f4400000-0000-4000-8000-000000000304'::uuid;
  v_unresolved_parent constant uuid:='f4400000-0000-4000-8000-000000000305'::uuid;
  v_outside constant uuid:='f4400000-0000-4000-8000-000000000306'::uuid;
  v_result jsonb;
  v_before_units jsonb;
  v_after_units jsonb;
  v_before_candidates jsonb;
  v_after_candidates jsonb;
  v_def text;
begin
  if to_regprocedure(
    'public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Organization Unit promotion preview membrane is missing.';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_organization_unit_self_api_v1(uuid)'
  ) is not null then
    raise exception 'Read-only Organization Unit preview package unexpectedly contains mutation command.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  -- The clone harness applies fixture DML before the candidate migration.
  -- Convert the lawful pre-migration placeholder candidates only after the
  -- migration has extended Reality Sentence grammar to organization_unit.establish.
  update atlas.implementation_reality_candidates c
  set operation_id='organization_unit.establish',
      subject_binding=jsonb_build_object(
        'kind','organization_unit',
        'label',case c.id
          when v_ready then 'Operations'
          when v_nested then 'Field Operations'
          when v_missing_kind then 'No Kind Unit'
          when v_duplicate then 'Existing Unit'
          when v_unresolved_parent then 'Nested Unit'
          when v_outside then 'Outside Unit'
        end,
        'resolution','proposed'
      ),
      context_binding=case c.id
        when v_nested then jsonb_build_object(
          'kind','organization_unit',
          'label','Existing Parent',
          'resolution','canonical',
          'canonicalId','f4400000-0000-4000-8000-000000000211'
        )
        when v_unresolved_parent then jsonb_build_object(
          'kind','organization_unit',
          'label','Unknown Parent',
          'resolution','unresolved'
        )
        else null
      end
  where c.id in (
    v_ready,v_nested,v_missing_kind,v_duplicate,v_unresolved_parent,v_outside
  );

  select jsonb_agg(to_jsonb(u) order by u.id)
  into v_before_units
  from atlas.organization_units u;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_before_candidates
  from atlas.implementation_reality_candidates c;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_ready);

  if v_result->>'state'<>'ready'
     or not coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true)
     or v_result->'consequence'->>'kind'<>'organization_unit'
     or v_result->'consequence'->>'unitKind'<>'department'
     or v_result->'consequence'->>'name'<>'Operations' then
    raise exception 'Valid Organization Unit candidate was not read-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_nested);
  if v_result->>'state'<>'ready'
     or v_result->'consequence'->>'parentUnitId'<>'f4400000-0000-4000-8000-000000000211' then
    raise exception 'Canonical parent Organization Unit was not preserved: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_missing_kind);
  if v_result->>'state'<>'semantic_payload_required'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Missing unitKind became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_duplicate);
  if v_result->>'state'<>'canonical_identity_exists'
     or v_result->>'existingOrganizationUnitId'<>'f4400000-0000-4000-8000-000000000212'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Existing Organization Unit identity was silently duplicated: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_unresolved_parent);
  if v_result->>'state'<>'identity_resolution_required'
     or v_result->>'slot'<>'context'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Unresolved parent binding became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_outside);
  if v_result->>'state'<>'outside_implementation_scope'
     or coalesce((v_result->>'canPromote')::boolean,false) then
    raise exception 'Out-of-scope Organization became promotion-ready: %',v_result;
  end if;

  select jsonb_agg(to_jsonb(u) order by u.id)
  into v_after_units
  from atlas.organization_units u;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_after_candidates
  from atlas.implementation_reality_candidates c;

  if v_after_units is distinct from v_before_units
     or v_after_candidates is distinct from v_before_candidates then
    raise exception 'Organization Unit promotion preview mutated canonical or candidate state.';
  end if;

  create function public.promote_implementation_reality_organization_unit_self_api_v1(
    p_candidate_id uuid
  )
  returns jsonb
  language sql
  as $$
    select jsonb_build_object('ok',true)
  $$;

  revoke all on function public.promote_implementation_reality_organization_unit_self_api_v1(uuid)
    from public,anon,authenticated,service_role;
  grant execute on function public.promote_implementation_reality_organization_unit_self_api_v1(uuid)
    to authenticated;

  v_result:=public.preview_implementation_reality_organization_unit_promotion_self_api_v1(v_ready);
  if not coalesce((v_result->>'canPromote')::boolean,false)
     or not coalesce((v_result->>'promotionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'canExecutePromotion')::boolean,false) then
    raise exception 'Organization Unit preview did not self-activate after exact mutation membrane became executable: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Organization Unit preview leaked around the public practitioner membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute Organization Unit preview.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%establish_organization_unit%' then
    raise exception 'Internal Organization Unit preview contains mutation authority.';
  end if;

  select lower(pg_get_functiondef(
    'public.preview_implementation_reality_organization_unit_promotion_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%to_regprocedure%'
     or v_def not like '%has_function_privilege%'
     or v_def not like '%promotioncommandavailable%'
     or v_def not like '%canexecutepromotion%' then
    raise exception 'Public Organization Unit preview lost dynamic mutation-capability signaling.';
  end if;
end;
$validation$;

rollback;
