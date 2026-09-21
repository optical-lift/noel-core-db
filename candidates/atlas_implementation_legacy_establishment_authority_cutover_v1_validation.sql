begin;

do $validation$
declare
  v_uid constant uuid := 'f4400000-0000-4000-8000-000000000001'::uuid;
  v_case constant uuid := 'f4400000-0000-4000-8000-000000000111'::uuid;
  v_result jsonb;
  v_def text;
  v_failed boolean;
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'Legacy authority cutover lacks live Reality Candidate prerequisite.';
  end if;

  if not exists(
    select 1
    from atlas.implementation_establishment_items
    where id='f4400000-0000-4000-8000-000000000131'::uuid
      and status='established'
  ) then
    raise exception 'Historical established coordination material was rewritten by authority cutover.';
  end if;

  perform set_config('request.jwt.claim.sub',v_uid::text,true);

  v_result:=atlas.save_implementation_establishment_item_self_api_v1(
    v_case,
    'institution',
    'Still-valid proposed coordination material',
    'Compatibility write after authority cutover.',
    'proposed'
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or v_result->>'status'<>'proposed'
     or coalesce((v_result->>'canonicalMutation')::boolean,true) then
    raise exception 'Legacy compatibility writer no longer preserves proposed noncanonical material: %',v_result;
  end if;

  v_failed:=false;
  begin
    perform atlas.save_implementation_establishment_item_self_api_v1(
      v_case,
      'institution',
      'Text pretending to be truth',
      'Must be rejected.',
      'established'
    );
  exception when sqlstate '22023' then
    v_failed:=true;
  end;

  if not v_failed then
    raise exception 'Legacy establishment-item writer can still self-author established status.';
  end if;

  select regexp_replace(
    pg_get_functiondef(
      'atlas.save_implementation_establishment_item_self_api_v1(uuid,text,text,text,text)'::regprocedure
    ),
    '[[:space:]]+',
    '',
    'g'
  )
  into v_def;

  if position(
       'p_statusnotin(''proposed'',''unresolved'')'
       in v_def
     )=0
     or position(
       'candidate_only_after_reality_sentence_v1'
       in v_def
     )=0
     or position(
       'canonicalMutation'',false'
       in v_def
     )=0 then
    raise exception 'Legacy authority cutover lost its noncanonical compatibility boundary.';
  end if;

  if position(
       'deletefromatlas.implementation_establishment_items'
       in lower(v_def)
     )>0
     or position(
       'updateatlas.implementation_establishment_items'
       in lower(v_def)
     )>0 then
    raise exception 'Legacy authority cutover writer unexpectedly rewrites historical establishment material.';
  end if;
end;
$validation$;

rollback;
