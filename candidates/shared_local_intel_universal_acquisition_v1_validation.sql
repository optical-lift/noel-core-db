begin;

do $validation$
declare
  v_apply jsonb;
  v_adjudication jsonb;
  v_entity_count bigint;
  v_membership_count bigint;
  v_origin uuid;
begin
  if to_regprocedure('local_intel.ensure_entity_context_membership_from_research_v1(uuid,uuid,text,uuid,jsonb)') is null then
    raise exception 'Universal context-membership helper is missing';
  end if;

  select count(*) into v_membership_count
  from local_intel.entity_context_memberships
  where entity_id='f2000000-0000-4000-8000-000000000121'::uuid
    and local_context_id='f2000000-0000-4000-8000-000000000112'::uuid;
  if v_membership_count<>0 then
    raise exception 'Context B unexpectedly knows canonical business before B research';
  end if;

  v_apply:=local_intel.ingest_search_discovery_evidence_v1(
    jsonb_build_object(
      'search_query_id','f2000000-0000-4000-8000-000000000141',
      'source_id','f2000000-0000-4000-8000-000000000131',
      'source_record_key','validation-cross-context-email',
      'subject_kind','business',
      'entity_id','f2000000-0000-4000-8000-000000000121',
      'observed_name','Validation One Copy Bank',
      'email','contact@one-copy-bank.example.invalid',
      'fields',jsonb_build_object('email','contact@one-copy-bank.example.invalid'),
      'metadata',jsonb_build_object('validationFixture',true)
    )
  );

  if (v_apply->>'entity_id')::uuid<>'f2000000-0000-4000-8000-000000000121'::uuid then
    raise exception 'Cross-context evidence did not reuse canonical entity: %',v_apply;
  end if;

  select count(*) into v_entity_count
  from local_intel.entities
  where stable_key='validation-universal-acq-business-one';
  if v_entity_count<>1 then
    raise exception 'Cross-context evidence created a duplicate canonical entity';
  end if;

  select local_context_id into v_origin
  from local_intel.entities
  where id='f2000000-0000-4000-8000-000000000121'::uuid;
  if v_origin<>'f2000000-0000-4000-8000-000000000111'::uuid then
    raise exception 'Legacy discovery-origin pointer was rewritten by Context B research';
  end if;

  select count(*) into v_membership_count
  from local_intel.entity_context_memberships
  where entity_id='f2000000-0000-4000-8000-000000000121'::uuid
    and local_context_id in (
      'f2000000-0000-4000-8000-000000000111'::uuid,
      'f2000000-0000-4000-8000-000000000112'::uuid
    )
    and status='active';
  if v_membership_count<>2 then
    raise exception 'Canonical business should be known in both contexts after B research';
  end if;

  if not exists(
    select 1
    from local_intel.contact_points cp
    where cp.entity_id='f2000000-0000-4000-8000-000000000121'::uuid
      and cp.contact_type='email'
      and cp.normalized_value='contact@one-copy-bank.example.invalid'
  ) then
    raise exception 'Cross-context source-backed email was not applied to canonical entity';
  end if;

  insert into local_intel.entity_ingestion_candidates(
    id,local_context_id,ingestion_source_id,source_record_key,
    proposed_entity_type,proposed_name,website_url,confidence,review_state,
    resolver_recommended_entity_id,resolver_recommendation_state,
    resolver_algorithm_key,resolver_algorithm_version,resolver_recommendation_basis,
    resolver_recommendation_evidence,resolver_recommended_at,metadata
  ) values (
    'f2000000-0000-4000-8000-000000000161'::uuid,
    'f2000000-0000-4000-8000-000000000112'::uuid,
    'f2000000-0000-4000-8000-000000000151'::uuid,
    'validation-cross-context-candidate',
    'business',
    'Validation Second Canonical Bank',
    'https://second-canonical-bank.example.invalid',
    1.0,
    'needs_review',
    'f2000000-0000-4000-8000-000000000122'::uuid,
    'strong_review_candidate',
    'governed_evidence_veto_resolver',
    '2.2',
    'validation_exact_name_and_domain',
    '{"validationFixture":true}'::jsonb,
    now(),
    '{"validationFixture":true}'::jsonb
  );

  if exists(
    select 1
    from local_intel.entity_context_memberships
    where entity_id='f2000000-0000-4000-8000-000000000122'::uuid
      and local_context_id='f2000000-0000-4000-8000-000000000112'::uuid
  ) then
    raise exception 'Resolver recommendation alone should not establish Context B membership';
  end if;

  v_adjudication:=local_intel.adjudicate_entity_ingestion_match_v1(
    'f2000000-0000-4000-8000-000000000161'::uuid,
    'approved',
    'validation-reviewer',
    'Validation proof of universal canonical reuse.',
    '{"validationFixture":true}'::jsonb
  );

  if (v_adjudication->>'matched_entity_id')::uuid<>'f2000000-0000-4000-8000-000000000122'::uuid then
    raise exception 'Approved candidate did not reuse canonical cross-context entity: %',v_adjudication;
  end if;

  if not exists(
    select 1
    from local_intel.entity_context_memberships
    where entity_id='f2000000-0000-4000-8000-000000000122'::uuid
      and local_context_id='f2000000-0000-4000-8000-000000000112'::uuid
      and status='active'
  ) then
    raise exception 'Approved universal candidate match did not establish requesting-context membership';
  end if;

  select count(*) into v_entity_count
  from local_intel.entities
  where id in (
    'f2000000-0000-4000-8000-000000000121'::uuid,
    'f2000000-0000-4000-8000-000000000122'::uuid
  );
  if v_entity_count<>2 then
    raise exception 'Universal acquisition proof changed canonical entity count';
  end if;

  if has_function_privilege('authenticated','local_intel.ensure_entity_context_membership_from_research_v1(uuid,uuid,text,uuid,jsonb)','EXECUTE')
     or has_function_privilege('service_role','local_intel.ensure_entity_context_membership_from_research_v1(uuid,uuid,text,uuid,jsonb)','EXECUTE') then
    raise exception 'Private context-membership helper leaked direct application execution';
  end if;

  if has_function_privilege('authenticated','local_intel.ingest_search_discovery_evidence_v1(jsonb)','EXECUTE') then
    raise exception 'Authenticated role unexpectedly has direct discovery intake execution';
  end if;

  if not has_function_privilege('service_role','local_intel.ingest_search_discovery_evidence_v1(jsonb)','EXECUTE') then
    raise exception 'Service role lacks governed discovery intake execution';
  end if;
end;
$validation$;

rollback;
