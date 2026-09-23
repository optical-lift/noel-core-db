begin;

do $validation$
declare
  v_user constant uuid := 'f4600000-0000-4000-8000-000000000001'::uuid;
  v_case constant uuid := 'f4600000-0000-4000-8000-000000000111'::uuid;
  v_v2_id uuid;
  v_v1_id uuid;
  v_result jsonb;
  v_read jsonb;
  v_item jsonb;
  v_failed boolean := false;
  v_def text;
begin
  if not exists(
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='implementation_reality_candidates'
      and column_name='semantic_payload'
      and data_type='jsonb'
      and is_nullable='NO'
  ) then
    raise exception 'Reality Candidate semantic_payload column is missing or nullable.';
  end if;

  if to_regprocedure(
    'public.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)'
  ) is null
     or to_regprocedure(
       'public.implementation_reality_candidates_self_api_v2(uuid)'
     ) is null then
    raise exception 'Reality Candidate v2 browser membranes are missing.';
  end if;

  if to_regprocedure(
    'public.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'
  ) is null
     or to_regprocedure(
       'public.implementation_reality_candidates_self_api_v1(uuid)'
     ) is null then
    raise exception 'Reality Candidate v1 membranes were not preserved.';
  end if;

  perform set_config('request.jwt.claim.sub',v_user::text,true);

  -- v2 may carry operation-specific meaning without calling it evidence,
  -- establishment authority, or provenance.
  v_result:=public.create_implementation_reality_candidate_self_api_v2(
    v_case,
    'person_position_appointment.establish',
    'manual_semantic_construction',
    'Known Person occupies Operations Steward.',
    '{"kind":"person","label":"Known Person","resolution":"canonical","canonicalId":"11111111-1111-4111-8111-111111111111"}'::jsonb,
    null,
    '{"kind":"organization_position","label":"Operations Steward","resolution":"canonical","canonicalId":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"kind":"organization","label":"Validation Organization","resolution":"canonical","canonicalId":"33333333-3333-4333-8333-333333333333"}'::jsonb,
    '{"appointmentKind":"primary","beginsAt":"2026-09-01T00:00:00Z"}'::jsonb,
    '["fixture:testimony:appointment"]'::jsonb,
    '{"kind":"reconstruction_of_existing_reality","reference":"fixture:testimony:appointment"}'::jsonb,
    'proposed'
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or coalesce((v_result->>'canonicalMutation')::boolean,true)
     or v_result->>'contractVersion'<>'implementation_reality_candidate_v2' then
    raise exception 'Reality Candidate v2 writer did not remain candidate-only: %',v_result;
  end if;

  v_v2_id:=(v_result->>'candidateId')::uuid;

  if not exists(
    select 1
    from atlas.implementation_reality_candidates c
    where c.id=v_v2_id
      and c.contract_version='implementation_reality_candidate_v2'
      and c.semantic_payload='{"appointmentKind":"primary","beginsAt":"2026-09-01T00:00:00Z"}'::jsonb
      and c.evidence_refs='["fixture:testimony:appointment"]'::jsonb
      and c.establishment_basis='{"kind":"reconstruction_of_existing_reality","reference":"fixture:testimony:appointment"}'::jsonb
      and c.provenance->>'source'='create_implementation_reality_candidate_self_api_v2'
      and c.candidate_state='proposed'
      and c.canonical_consequence_kind is null
  ) then
    raise exception 'Reality Candidate v2 did not preserve semantic payload as a distinct custody field.';
  end if;

  -- Proposed meaning may still be corrected before promotion.
  update atlas.implementation_reality_candidates
  set semantic_payload='{"appointmentKind":"secondary","beginsAt":"2026-09-01T00:00:00Z"}'::jsonb
  where id=v_v2_id;

  if not exists(
    select 1
    from atlas.implementation_reality_candidates
    where id=v_v2_id
      and semantic_payload->>'appointmentKind'='secondary'
  ) then
    raise exception 'Unpromoted semantic payload could not be corrected.';
  end if;

  v_read:=public.implementation_reality_candidates_self_api_v2(v_case);

  select x.value
  into v_item
  from jsonb_array_elements(v_read->'items') x(value)
  where x.value->>'id'=v_v2_id::text;

  if v_item is null
     or v_item->>'candidateContractVersion'<>'implementation_reality_candidate_v2'
     or v_item->'semanticPayload'->>'appointmentKind'<>'secondary' then
    raise exception 'Reality Candidate v2 reader omitted semantic payload or contract identity: %',v_item;
  end if;

  -- Existing v1 clients keep their exact writer contract. Their rows receive
  -- the additive empty payload default and remain v1 custody.
  v_result:=public.create_implementation_reality_candidate_self_api_v1(
    v_case,
    'person.establish',
    'manual_semantic_construction',
    'Compatibility Person is a Person.',
    '{"kind":"person","label":"Compatibility Person","resolution":"proposed"}'::jsonb,
    null,
    null,
    null,
    '[]'::jsonb,
    null,
    'proposed'
  );

  v_v1_id:=(v_result->>'candidateId')::uuid;

  if not exists(
    select 1
    from atlas.implementation_reality_candidates c
    where c.id=v_v1_id
      and c.contract_version='implementation_reality_candidate_v1'
      and c.semantic_payload='{}'::jsonb
      and c.candidate_state='proposed'
  ) then
    raise exception 'Reality Candidate v1 compatibility was broken by semantic payload v2.';
  end if;

  -- The v2 membrane rejects malformed semantic payload before persistence.
  v_failed:=false;
  begin
    perform public.create_implementation_reality_candidate_self_api_v2(
      v_case,
      'person.establish',
      'manual_semantic_construction',
      'Malformed semantic payload.',
      '{"kind":"person","label":"Malformed","resolution":"proposed"}'::jsonb,
      null,
      null,
      null,
      '["not-an-object"]'::jsonb,
      '[]'::jsonb,
      null,
      'proposed'
    );
  exception when sqlstate '22023' then
    v_failed:=true;
  end;

  if not v_failed then
    raise exception 'Reality Candidate v2 accepted a non-object semantic payload.';
  end if;

  -- Once canonical promotion occurs, the exact semantic proposal becomes
  -- immutable provenance. Clone-only direct insertion models an already
  -- promoted candidate without invoking any owning domain.
  insert into atlas.implementation_reality_candidates(
    id,
    implementation_case_id,
    contract_version,
    operation_id,
    origin_kind,
    literal_statement,
    subject_binding,
    semantic_payload,
    evidence_refs,
    candidate_state,
    canonical_consequence_kind,
    canonical_consequence_ref,
    promoted_at,
    promoted_by_user_id,
    author_user_id,
    provenance
  ) values (
    'f4600000-0000-4000-8000-000000000301'::uuid,
    v_case,
    'implementation_reality_candidate_v2',
    'person.establish',
    'manual_semantic_construction',
    'Promoted fixture Person.',
    '{"kind":"person","label":"Promoted fixture Person","resolution":"proposed"}'::jsonb,
    '{"displayQualifier":"fixture"}'::jsonb,
    '[]'::jsonb,
    'promoted',
    'validation_only',
    'fixture:canonical:person',
    now(),
    v_user,
    v_user,
    '{"validationFixture":true}'::jsonb
  );

  v_failed:=false;
  begin
    update atlas.implementation_reality_candidates
    set semantic_payload='{"displayQualifier":"rewritten"}'::jsonb
    where id='f4600000-0000-4000-8000-000000000301'::uuid;
  exception when sqlstate '23514' then
    v_failed:=true;
  end;

  if not v_failed then
    raise exception 'Promoted Reality Candidate semantic payload remained mutable.';
  end if;

  -- Browser roles receive only the public v2 membranes, never table or
  -- internal-function authority.
  if has_function_privilege(
       'anon',
       'public.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Reality Candidate v2 leaked writer authority.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.implementation_reality_candidates_self_api_v2(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner cannot execute the v2 public membranes.';
  end if;

  if has_table_privilege(
       'authenticated',
       'atlas.implementation_reality_candidates',
       'UPDATE'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_reality_candidates',
       'INSERT'
     ) then
    raise exception 'Semantic payload v2 leaked direct table mutation authority.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.create_implementation_reality_candidate_self_api_v2(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,text)'::regprocedure
  )) into v_def;

  if v_def not like '%implementation_practitioner_assigned_to_case_self_v1%'
     or v_def not like '%candidate_state%'
     or v_def not like '%canonicalmutation%'
     or v_def like '%insert into atlas.organization_%'
     or v_def like '%insert into atlas.people%'
     or v_def like '%insert into atlas.work_%' then
    raise exception 'Reality Candidate v2 writer widened beyond candidate custody.';
  end if;
end;
$validation$;

rollback;
