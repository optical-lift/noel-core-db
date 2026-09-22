begin;

do $validation$
declare
  v_practitioner constant uuid := 'f4300000-0000-4000-8000-000000000001'::uuid;
  v_org constant uuid := 'f4300000-0000-4000-8000-000000000201'::uuid;
  v_person constant uuid := 'f4300000-0000-4000-8000-000000000211'::uuid;
  v_candidate constant uuid := 'f4300000-0000-4000-8000-000000000301'::uuid;
  v_outside_candidate constant uuid := 'f4300000-0000-4000-8000-000000000302'::uuid;
  v_missing_basis_candidate constant uuid := 'f4300000-0000-4000-8000-000000000303'::uuid;
  v_sponsor_participant constant uuid := 'f4300000-0000-4000-8000-000000000122'::uuid;
  v_result jsonb;
  v_before_candidates jsonb;
  v_after_candidates jsonb;
  v_before_ipr bigint;
  v_after_ipr bigint;
  v_def text;
begin
  if to_regprocedure(
    'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Reality Candidate promotion preview membrane is missing.';
  end if;

  if to_regprocedure(
    'public.promote_implementation_reality_candidate_self_api_v1(uuid)'
  ) is not null then
    raise exception 'Read-only promotion preview package unexpectedly contains promotion mutation.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select count(*) into v_before_ipr
  from atlas.institutional_person_records;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_before_candidates
  from atlas.implementation_reality_candidates c;

  update atlas.implementation_case_participants
  set active=false,ended_at=now(),updated_at=now()
  where id=v_sponsor_participant;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if v_result->>'state'<>'setup_sponsor_authority_required'
     or coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true) then
    raise exception 'Promotion preview did not fail closed without live setup sponsor or mutation command: %',v_result;
  end if;

  update atlas.implementation_case_participants
  set active=true,ended_at=null,updated_at=now()
  where id=v_sponsor_participant;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if v_result->>'state'<>'ready'
     or not coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true)
     or v_result->'consequence'->>'kind'<>'institutional_person_record'
     or v_result->'consequence'->>'mode'<>'create_relation' then
    raise exception 'Valid candidate was not read-ready while mutation remained unavailable: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_outside_candidate
  );
  if v_result->>'state'<>'outside_implementation_scope'
     or coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true) then
    raise exception 'Out-of-scope candidate became promotion-ready: %',v_result;
  end if;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_missing_basis_candidate
  );
  if v_result->>'state'<>'establishment_basis_required'
     or coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true) then
    raise exception 'Candidate without establishment basis became promotion-ready: %',v_result;
  end if;

  select count(*) into v_after_ipr
  from atlas.institutional_person_records;

  select jsonb_agg(to_jsonb(c) order by c.id)
  into v_after_candidates
  from atlas.implementation_reality_candidates c;

  if v_after_ipr<>v_before_ipr or v_after_candidates is distinct from v_before_candidates then
    raise exception 'Promotion preview mutated canonical or candidate state.';
  end if;

  create function public.promote_implementation_reality_candidate_self_api_v1(
    p_candidate_id uuid
  )
  returns jsonb
  language sql
  as $$
    select jsonb_build_object('ok',true)
  $$;

  revoke all on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
    from public,anon,authenticated,service_role;
  grant execute on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
    to authenticated;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'canPromote')::boolean,false)
     or not coalesce((v_result->>'promotionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'canExecutePromotion')::boolean,false) then
    raise exception 'Promotion preview did not self-activate after mutation membrane became executable: %',v_result;
  end if;

  revoke execute on function public.promote_implementation_reality_candidate_self_api_v1(uuid)
    from authenticated;

  v_result:=public.preview_implementation_reality_candidate_promotion_self_api_v1(
    v_candidate
  );

  if not coalesce((v_result->>'canPromote')::boolean,false)
     or coalesce((v_result->>'promotionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canExecutePromotion')::boolean,true) then
    raise exception 'Promotion preview ignored executable privilege withdrawal: %',v_result;
  end if;

  if has_function_privilege(
       'anon',
       'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Promotion preview leaked around the public practitioner membrane.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute promotion preview.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%'
     or v_def like '%establish_institutional_person_from_reality_internal_v1%' then
    raise exception 'Internal promotion preview contains mutation authority.';
  end if;

  select lower(pg_get_functiondef(
    'public.preview_implementation_reality_candidate_promotion_self_api_v1(uuid)'::regprocedure
  )) into v_def;

  if v_def not like '%to_regprocedure%'
     or v_def not like '%has_function_privilege%'
     or v_def not like '%promotioncommandavailable%'
     or v_def not like '%canexecutepromotion%' then
    raise exception 'Public promotion preview lost dynamic mutation-capability signaling.';
  end if;
end;
$validation$;

rollback;
