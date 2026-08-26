-- Atlas architecture truth authority catalog v1
--
-- Purpose: make canonical truth ownership cheap to discover without running
-- whole-system census/audit machinery. This is metadata only: no farm truth,
-- task truth, crop state, scheduling, or worker behavior changes.

create table if not exists atlas.architecture_truth_authorities (
  authority_key text primary key,
  domain_key text not null,
  truth_question text not null,
  authority_owner text not null,
  authority_status text not null check (authority_status in ('canonical','incomplete','transitional','retired')),
  canonical_relations text[] not null default '{}'::text[],
  canonical_functions text[] not null default '{}'::text[],
  supporting_relations text[] not null default '{}'::text[],
  consumer_surfaces text[] not null default '{}'::text[],
  known_competitors text[] not null default '{}'::text[],
  source_custody text not null,
  rationale text not null,
  established_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(authority_key) <> ''),
  check (btrim(domain_key) <> ''),
  check (btrim(authority_owner) <> '')
);

create index if not exists architecture_truth_authorities_domain_idx
  on atlas.architecture_truth_authorities(domain_key, authority_status, authority_key);

comment on table atlas.architecture_truth_authorities is
  'Cheap machine-readable map from a truth question to its canonical Atlas owner, supporting evidence, known competitors, and source custody. It does not itself own business truth.';

revoke all on table atlas.architecture_truth_authorities from public, anon, authenticated;
grant select on table atlas.architecture_truth_authorities to service_role;

insert into atlas.architecture_truth_authorities (
  authority_key, domain_key, truth_question, authority_owner, authority_status,
  canonical_relations, canonical_functions, supporting_relations,
  consumer_surfaces, known_competitors, source_custody, rationale
) values
(
  'crop_occupancy_identity',
  'crop_lifecycle',
  'What crop body does Atlas claim occupies a growing object, and which canonical crop cycle represents it?',
  'atlas.crop_cycles',
  'canonical',
  array['atlas.crop_cycles'],
  array['atlas.ensure_crop_cycle_for_content_v1(uuid)','atlas.sync_crop_cycle_registry_v1(uuid,uuid)'],
  array['atlas.object_contents','atlas.crop_occupancy_evidence','atlas.planting_claims','atlas.v_crop_cycle_registry'],
  array['crop task focus','production','harvest','farm continuity'],
  array['atlas.object_contents.status as an independent lifecycle clock'],
  'optical-lift/noel-core-db:20260826174253_atlas_architecture_truth_authority_catalog_v1',
  'object_contents may witness occupancy and source identity, but crop_cycles is the durable lifecycle body. Occupancy evidence must reconcile into that body rather than maintain a second biological clock.'
),
(
  'crop_profile_identity',
  'crop_lifecycle',
  'Which biological timing model governs a crop identity?',
  'atlas.crop_profiles',
  'canonical',
  array['atlas.crop_profiles'],
  array['atlas.resolve_crop_profile_id_v1(text,text)','atlas.enrich_crop_cycle_profile_v1()'],
  array['atlas.crop_cycles','atlas.object_contents'],
  array['crop lifecycle','production forecasts','harvest watch'],
  array['task-local timing prose','object-content metadata as a substitute crop profile'],
  'optical-lift/noel-core-db:20260826174253_atlas_architecture_truth_authority_catalog_v1',
  'A crop profile owns reusable biological timing expectations. Individual occupancy/task records may point to a profile but must not invent an independent timing model.'
),
(
  'crop_observed_state',
  'crop_lifecycle',
  'What field observation has actually been recorded about a crop body?',
  'atlas.crop_observations',
  'canonical',
  array['atlas.crop_observations'],
  array[]::text[],
  array['atlas.crop_observation_types','atlas.crop_cycles'],
  array['crop task focus','harvest watch','crop continuity'],
  array['a last-observed label treated as a permanent expected state'],
  'optical-lift/noel-core-db:20260826174253_atlas_architecture_truth_authority_catalog_v1',
  'Observations are evidence that can confirm, contradict, or recalibrate biological expectation. Silence after an observation is not evidence that biology stopped progressing.'
),
(
  'crop_biological_progression',
  'crop_lifecycle',
  'Given the crop body, profile, biological anchor, and date, what biological continuation may Atlas infer without a new field observation?',
  'atlas.crop_cycle_biological_progression_state_v1(uuid,date)',
  'incomplete',
  array['atlas.crop_cycles','atlas.crop_profiles'],
  array['atlas.crop_cycle_biological_progression_state_v1(uuid,date)'],
  array['atlas.crop_observations','atlas.task_crop_cycles','atlas.tasks'],
  array['crop task focus','production','harvest watch','farm continuity'],
  array['atlas.crop_cycle_stage_continuity_state_v1(uuid,date) used as the default biological clock','atlas.object_contents.status used as current expected stage'],
  'optical-lift/noel-core-db:20260826174253_atlas_architecture_truth_authority_catalog_v1',
  'The existing biological progression function correctly permits annual crops to continue through time toward a canonical harvest-watch boundary, but it is deliberately narrow: it does not yet calculate the full expected lifecycle stage for annual, biennial, and perennial crops. It is therefore the seed of the expected-state authority, not yet a complete answer.'
),
(
  'crop_stage_continuity_exception',
  'crop_lifecycle',
  'When does a recorded crop state require observation or reconciliation because reality may have diverged from ordinary progression?',
  'atlas.crop_cycle_stage_continuity_state_v1(uuid,date)',
  'transitional',
  array['atlas.crop_cycles','atlas.crop_profiles'],
  array['atlas.crop_cycle_stage_continuity_state_v1(uuid,date)'],
  array['atlas.crop_observations','atlas.task_crop_cycles','atlas.tasks'],
  array['farm continuity','propagation','harvest'],
  array['using every transition-state observation requirement to freeze expected lifecycle progression'],
  'optical-lift/noel-core-db:20260826174253_atlas_architecture_truth_authority_catalog_v1',
  'This function is useful as an exception/reconciliation detector, especially for damage, decline, cut-back, and contradictory evidence. It must not become the ordinary expected-state clock, because several normal transition states currently demand fresh observation instead of allowing time-based progression.'
)
on conflict (authority_key) do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

create or replace function atlas.architecture_truth_authority_lookup_v1(
  p_domain_key text default null,
  p_authority_key text default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $$
  select jsonb_build_object(
    'contractVersion','architecture_truth_authority_lookup_v1',
    'domainKey',p_domain_key,
    'authorityKey',p_authority_key,
    'count',count(*),
    'authorities',coalesce(
      jsonb_agg(
        jsonb_build_object(
          'authorityKey',a.authority_key,
          'domainKey',a.domain_key,
          'truthQuestion',a.truth_question,
          'authorityOwner',a.authority_owner,
          'authorityStatus',a.authority_status,
          'canonicalRelations',a.canonical_relations,
          'canonicalFunctions',a.canonical_functions,
          'supportingRelations',a.supporting_relations,
          'consumerSurfaces',a.consumer_surfaces,
          'knownCompetitors',a.known_competitors,
          'sourceCustody',a.source_custody,
          'rationale',a.rationale
        ) order by a.domain_key,a.authority_key
      ) filter (where a.authority_key is not null),
      '[]'::jsonb
    )
  )
  from atlas.architecture_truth_authorities a
  where (p_domain_key is null or a.domain_key=p_domain_key)
    and (p_authority_key is null or a.authority_key=p_authority_key);
$$;

revoke all on function atlas.architecture_truth_authority_lookup_v1(text,text) from public, anon, authenticated;
grant execute on function atlas.architecture_truth_authority_lookup_v1(text,text) to service_role;

create or replace function atlas.assert_architecture_truth_authorities_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_missing_relations jsonb;
  v_missing_functions jsonb;
  v_empty_authorities jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('authorityKey',a.authority_key,'relation',r)), '[]'::jsonb)
  into v_missing_relations
  from atlas.architecture_truth_authorities a
  cross join lateral unnest(a.canonical_relations) r
  where to_regclass(r) is null;

  select coalesce(jsonb_agg(jsonb_build_object('authorityKey',a.authority_key,'function',f)), '[]'::jsonb)
  into v_missing_functions
  from atlas.architecture_truth_authorities a
  cross join lateral unnest(a.canonical_functions) f
  where to_regprocedure(f) is null;

  select coalesce(jsonb_agg(a.authority_key), '[]'::jsonb)
  into v_empty_authorities
  from atlas.architecture_truth_authorities a
  where cardinality(a.canonical_relations)=0 and cardinality(a.canonical_functions)=0;

  if jsonb_array_length(v_missing_relations)>0
     or jsonb_array_length(v_missing_functions)>0
     or jsonb_array_length(v_empty_authorities)>0 then
    raise exception using
      errcode='23514',
      message='architecture_truth_authority_catalog_invalid',
      detail=jsonb_build_object(
        'missingRelations',v_missing_relations,
        'missingFunctions',v_missing_functions,
        'emptyAuthorities',v_empty_authorities
      )::text;
  end if;

  return jsonb_build_object(
    'status','sound',
    'authorityCount',(select count(*) from atlas.architecture_truth_authorities),
    'domainCount',(select count(distinct domain_key) from atlas.architecture_truth_authorities),
    'missingRelationCount',0,
    'missingFunctionCount',0,
    'emptyAuthorityCount',0
  );
end;
$$;

revoke all on function atlas.assert_architecture_truth_authorities_v1() from public, anon, authenticated;
grant execute on function atlas.assert_architecture_truth_authorities_v1() to service_role;

insert into atlas.authenticated_rpc_registry (
  signature, classification, confidence, review_status,
  authenticated_execute_expected, security_definer_expected,
  service_execute_expected, caller_count, policy_reference_count,
  evidence, anonymous_execute_expected
)
values
(
  'atlas.architecture_truth_authority_lookup_v1(text,text)',
  'service_internal','verified','revoked',false,true,true,0,0,
  jsonb_build_object(
    'source','atlas_architecture_truth_authority_catalog_v1',
    'boundary','Cheap service-only architecture lookup; not an application RPC.',
    'ownsBusinessTruth',false
  ),false
),
(
  'atlas.assert_architecture_truth_authorities_v1()',
  'service_internal','verified','revoked',false,true,true,0,0,
  jsonb_build_object(
    'source','atlas_architecture_truth_authority_catalog_v1',
    'boundary','Release/CI assertion for authority-map referential soundness; not an application RPC.',
    'ownsBusinessTruth',false
  ),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

select atlas.assert_architecture_truth_authorities_v1();
