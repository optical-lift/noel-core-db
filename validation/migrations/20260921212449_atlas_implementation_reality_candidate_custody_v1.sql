begin;

do $validation$
declare
  v_count integer;
  v_def text;
  v_failed boolean;
begin
  if to_regclass('atlas.implementation_reality_candidates') is null then
    raise exception 'implementation_reality_candidates table is missing';
  end if;

  if to_regprocedure(
    'atlas.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'
  ) is null then
    raise exception 'Atlas Reality Candidate self writer is missing';
  end if;

  if to_regprocedure(
    'public.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'
  ) is null then
    raise exception 'Public Reality Candidate self writer membrane is missing';
  end if;

  if to_regprocedure(
    'public.implementation_reality_candidates_self_api_v1(uuid)'
  ) is null then
    raise exception 'Public Reality Candidate read membrane is missing';
  end if;

  -- All four admitted origins share one candidate custody object while keeping
  -- their origin explicit. These direct inserts are clone-only contract proof;
  -- browser mutation remains behind the self API proved below.
  insert into atlas.implementation_reality_candidates(
    id,
    implementation_case_id,
    implementation_thread_id,
    operation_id,
    origin_kind,
    literal_statement,
    subject_binding,
    object_binding,
    context_binding,
    evidence_refs,
    establishment_basis,
    candidate_state,
    provenance
  ) values
  (
    'f4100000-0000-4000-8000-000000000201'::uuid,
    'f4100000-0000-4000-8000-000000000111'::uuid,
    'f4100000-0000-4000-8000-000000000121'::uuid,
    'person_position_appointment.establish',
    'manual_semantic_construction',
    'Anna occupies Farm Steward at Elm Farm.',
    '{"kind":"person","label":"Anna","resolution":"canonical","canonicalId":"11111111-1111-4111-8111-111111111111"}'::jsonb,
    '{"kind":"organization_position","label":"Farm Steward","resolution":"canonical","canonicalId":"22222222-2222-4222-8222-222222222222"}'::jsonb,
    '{"kind":"organization","label":"Elm Farm","resolution":"canonical","canonicalId":"33333333-3333-4333-8333-333333333333"}'::jsonb,
    '["fixture:testimony:anna"]'::jsonb,
    '{"kind":"reconstruction_of_existing_reality","reference":"fixture:existing-relationship"}'::jsonb,
    'proposed',
    '{"validationFixture":true}'::jsonb
  ),
  (
    'f4100000-0000-4000-8000-000000000202'::uuid,
    'f4100000-0000-4000-8000-000000000111'::uuid,
    null,
    'person.establish',
    'plain_language_capture',
    'Sarah is a person the organization knows about.',
    '{"kind":"person","label":"Sarah","resolution":"proposed"}'::jsonb,
    null,
    null,
    '["fixture:plain-language"]'::jsonb,
    null,
    'unresolved',
    '{"validationFixture":true}'::jsonb
  ),
  (
    'f4100000-0000-4000-8000-000000000203'::uuid,
    'f4100000-0000-4000-8000-000000000111'::uuid,
    null,
    'organization_responsibility.establish',
    'ai_proposal',
    'Operations Lead carries purchasing review.',
    '{"kind":"organization_responsibility","label":"Purchasing review","resolution":"proposed"}'::jsonb,
    '{"kind":"organization","label":"Validation Reality Candidate One","resolution":"canonical","canonicalId":"44444444-4444-4444-8444-444444444444"}'::jsonb,
    null,
    '["fixture:ai-proposal"]'::jsonb,
    null,
    'proposed',
    '{"validationFixture":true,"machineDerivative":true}'::jsonb
  ),
  (
    'f4100000-0000-4000-8000-000000000204'::uuid,
    'f4100000-0000-4000-8000-000000000111'::uuid,
    null,
    'organization_position.establish',
    'source_derived',
    'Validation Organization has an Operations Lead position.',
    '{"kind":"organization_position","label":"Operations Lead","resolution":"proposed"}'::jsonb,
    '{"kind":"organization","label":"Validation Reality Candidate One","resolution":"canonical","canonicalId":"44444444-4444-4444-8444-444444444444"}'::jsonb,
    null,
    '["fixture:source-record"]'::jsonb,
    null,
    'proposed',
    '{"validationFixture":true,"sourceDerived":true}'::jsonb
  );

  select count(*)::integer
  into v_count
  from atlas.implementation_reality_candidates
  where implementation_case_id='f4100000-0000-4000-8000-000000000111'::uuid;

  if v_count <> 4 then
    raise exception 'Expected four shared-custody Reality Candidates; found %',v_count;
  end if;

  if exists (
    select 1
    from atlas.implementation_reality_candidates
    where id='f4100000-0000-4000-8000-000000000201'::uuid
      and (
        candidate_state <> 'proposed'
        or canonical_consequence_kind is not null
        or canonical_consequence_ref is not null
        or promoted_at is not null
      )
  ) then
    raise exception 'Manual Reality Candidate was promoted or given canonical consequence without an owning-domain command';
  end if;

  -- Missing required object/context must fail. PostgreSQL CHECK null semantics
  -- must not allow a structurally incomplete appointment candidate.
  v_failed := false;
  begin
    insert into atlas.implementation_reality_candidates(
      implementation_case_id,
      operation_id,
      origin_kind,
      literal_statement,
      subject_binding,
      candidate_state
    ) values (
      'f4100000-0000-4000-8000-000000000111'::uuid,
      'person_position_appointment.establish',
      'manual_semantic_construction',
      'Incomplete appointment candidate.',
      '{"kind":"person","label":"Anna","resolution":"proposed"}'::jsonb,
      'proposed'
    );
  exception
    when check_violation then
      v_failed := true;
  end;

  if not v_failed then
    raise exception 'Appointment candidate accepted without required Position and Organization bindings';
  end if;

  -- Operation/binding families are typed; a Person operation cannot carry an
  -- Organization subject merely because the human-readable sentence exists.
  v_failed := false;
  begin
    insert into atlas.implementation_reality_candidates(
      implementation_case_id,
      operation_id,
      origin_kind,
      literal_statement,
      subject_binding,
      candidate_state
    ) values (
      'f4100000-0000-4000-8000-000000000111'::uuid,
      'person.establish',
      'manual_semantic_construction',
      'Wrong typed subject.',
      '{"kind":"organization","label":"Not a Person","resolution":"proposed"}'::jsonb,
      'proposed'
    );
  exception
    when check_violation then
      v_failed := true;
  end;

  if not v_failed then
    raise exception 'Reality Candidate operation accepted the wrong semantic subject kind';
  end if;

  -- Candidate text cannot call itself promoted. Promotion is structurally
  -- impossible without an explicit owning-domain consequence reference.
  v_failed := false;
  begin
    insert into atlas.implementation_reality_candidates(
      implementation_case_id,
      operation_id,
      origin_kind,
      literal_statement,
      subject_binding,
      candidate_state,
      provenance
    ) values (
      'f4100000-0000-4000-8000-000000000111'::uuid,
      'person.establish',
      'manual_semantic_construction',
      'Pretend canonical person.',
      '{"kind":"person","label":"Pretend Person","resolution":"proposed"}'::jsonb,
      'promoted',
      '{"validationFixture":true}'::jsonb
    );
  exception
    when check_violation then
      v_failed := true;
  end;

  if not v_failed then
    raise exception 'Reality Candidate promoted without canonical consequence provenance';
  end if;

  -- Candidate custody cannot cross Implementation Case boundaries through a
  -- thread pointer.
  v_failed := false;
  begin
    insert into atlas.implementation_reality_candidates(
      implementation_case_id,
      implementation_thread_id,
      operation_id,
      origin_kind,
      literal_statement,
      subject_binding,
      candidate_state,
      provenance
    ) values (
      'f4100000-0000-4000-8000-000000000111'::uuid,
      'f4100000-0000-4000-8000-000000000122'::uuid,
      'person.establish',
      'manual_semantic_construction',
      'Cross-case thread candidate.',
      '{"kind":"person","label":"Cross Case","resolution":"proposed"}'::jsonb,
      'proposed',
      '{"validationFixture":true}'::jsonb
    );
  exception
    when check_violation then
      v_failed := true;
  end;

  if not v_failed then
    raise exception 'Reality Candidate accepted a thread from a different Implementation Case';
  end if;

  -- Browser roles get no direct table authority.
  if has_table_privilege(
       'anon',
       'atlas.implementation_reality_candidates',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_reality_candidates',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_reality_candidates',
       'INSERT'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.implementation_reality_candidates',
       'UPDATE'
     )
     or has_table_privilege(
       'service_role',
       'atlas.implementation_reality_candidates',
       'INSERT'
     ) then
    raise exception 'Reality Candidate table leaked direct application-role authority';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='implementation_reality_candidates'
      and c.relrowsecurity
  ) then
    raise exception 'Reality Candidate table RLS is not enabled';
  end if;

  -- Only authenticated practitioners may reach the browser membranes.
  if has_function_privilege(
       'anon',
       'public.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role can execute Reality Candidate writer';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Reality Candidate writer membrane';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.implementation_reality_candidates_self_api_v1(uuid)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Reality Candidate read membrane';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role bypasses the public Reality Candidate membrane';
  end if;

  -- The browser writer is deliberately manual-only and candidate-only.
  select regexp_replace(
    pg_get_functiondef(
      'atlas.create_implementation_reality_candidate_self_api_v1(uuid,text,text,text,jsonb,uuid,jsonb,jsonb,jsonb,jsonb,text)'::regprocedure
    ),
    '[[:space:]]+',
    '',
    'g'
  )
  into v_def;

  if position(
       'p_origin_kindnotin(''manual_semantic_construction'',''plain_language_capture'')'
       in v_def
     ) = 0 then
    raise exception 'Reality Candidate self writer no longer proves manual/plain-language origin restriction';
  end if;

  if position(
       'p_candidate_statenotin(''proposed'',''unresolved'')'
       in v_def
     ) = 0 then
    raise exception 'Reality Candidate self writer no longer proves proposed/unresolved-only creation';
  end if;

  if position(
       'implementation_practitioner_assigned_to_case_self_v1'
       in v_def
     ) = 0 then
    raise exception 'Reality Candidate self writer no longer proves assigned-practitioner authority';
  end if;

  -- Candidate custody is additive. The currently live legacy writer must remain
  -- behaviorally compatible until a separate authority-cutover migration.
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
       'p_statusnotin(''proposed'',''established'',''unresolved'')'
       in v_def
     ) = 0 then
    raise exception 'Additive Candidate custody changed legacy establishment-item status compatibility';
  end if;

  if position(
       'candidate_only_after_reality_sentence_v1'
       in v_def
     ) > 0
     or position(
       'canonicalMutation'',false'
       in v_def
     ) > 0 then
    raise exception 'Additive Candidate custody unexpectedly installed the deferred legacy authority cutover';
  end if;
end;
$validation$;

rollback;
