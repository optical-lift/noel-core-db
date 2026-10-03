create or replace function atlas.record_household_rhythm_shadow_observation_self_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_source jsonb;
  v_payload_source jsonb;
  v_comparison jsonb;
  v_source_windows jsonb;
  v_source_basis jsonb;
  v_comparison_basis jsonb;
  v_source_fingerprint text;
  v_comparison_fingerprint text;
  v_source_key text;
  v_baseline_ref text;
  v_baseline_version text;
  v_carrier_version text;
  v_server_version text;
  v_principal_id uuid;
  v_household_id uuid;
  v_payload_observed_at timestamptz;
  v_current_observed_at timestamptz;
  v_evidence_id uuid;
  v_created boolean := false;
  v_rhythm jsonb;
  v_match_count integer;
  v_observation_count integer;
  v_distinct_observation_count integer;
  v_equivalent_count integer;
  v_divergent_count integer;
  v_incomplete_count integer;
  v_expected_state text;
  v_existing atlas.evidence_records%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;
  if p_payload->>'contractVersion' <> 'household_rhythm_shadow_observation_custody_v1' then
    raise exception 'Unsupported shadow observation custody contract.' using errcode='22023';
  end if;

  v_baseline_ref := btrim(coalesce(p_payload->>'baselineRef',''));
  v_baseline_version := btrim(coalesce(p_payload->>'baselineVersion',''));
  v_carrier_version := btrim(coalesce(p_payload->>'carrierVersion',''));
  v_server_version := btrim(coalesce(p_payload->>'serverVersion',''));
  if v_baseline_ref <> 'atlas-shadow-baseline:household-rhythm:2026-10-01'
     or v_baseline_version <> 'household_rhythm_shadow_cutover_baseline_v1'
     or v_carrier_version <> 'household_rhythm_cutover_shadow_carrier_v1'
     or v_server_version <> 'household_rhythm_shadow_state_server_v1' then
    raise exception 'Shadow observation provenance contract does not match admitted v1 baseline.' using errcode='22023';
  end if;

  v_payload_source := p_payload->'sourceState';
  v_comparison := p_payload->'comparison';
  if jsonb_typeof(v_payload_source) <> 'object' or jsonb_typeof(v_comparison) <> 'object' then
    raise exception 'sourceState and comparison objects are required.' using errcode='22023';
  end if;
  if v_payload_source->>'contract_version' <> 'household_rhythm_shadow_state_self_api_v1'
     or v_payload_source->>'state' <> 'ready'
     or coalesce((v_payload_source->>'ok')::boolean,false) is not true then
    raise exception 'Only a ready v1 shadow source state may be preserved.' using errcode='22023';
  end if;
  if v_comparison->>'contract_version' <> 'household_rhythm_cutover_shadow_carrier_v1' then
    raise exception 'Comparison carrier contract mismatch.' using errcode='22023';
  end if;
  if coalesce((v_payload_source->'truth_boundary'->>'readOnly')::boolean,false) is not true
     or coalesce((v_payload_source->'truth_boundary'->>'authorityMutationAllowed')::boolean,true) is not false
     or coalesce((v_comparison->'truth_boundary'->>'readOnly')::boolean,false) is not true
     or coalesce((v_comparison->'truth_boundary'->>'legacyAuthorityMutated')::boolean,true) is not false
     or coalesce((v_comparison->'truth_boundary'->>'cutoverAnchorRebasedFromLiveState')::boolean,true) is not false
     or coalesce((v_comparison->'truth_boundary'->>'divergenceChangesAuthority')::boolean,true) is not false
     or coalesce((v_comparison->'truth_boundary'->>'equivalenceCreatesCanonicalTruth')::boolean,true) is not false then
    raise exception 'Shadow truth boundary is not non-authoritative.' using errcode='22023';
  end if;

  v_source := atlas.household_rhythm_shadow_state_self_api_v1();
  if v_source->>'state' <> 'ready' or coalesce((v_source->>'ok')::boolean,false) is not true then
    raise exception 'Current Household Rhythm shadow source is not ready.' using errcode='55000';
  end if;
  v_principal_id := (v_source->>'principalId')::uuid;
  v_household_id := (v_source->>'householdId')::uuid;
  v_current_observed_at := (v_source->>'observedAt')::timestamptz;
  v_payload_observed_at := (v_payload_source->>'observed_at')::timestamptz;

  if v_payload_source->>'principal_ref' <> 'atlas.principals:' || v_principal_id::text
     or v_payload_source->>'household_ref' <> 'atlas.households:' || v_household_id::text
     or v_payload_source->>'timezone' is distinct from v_source->>'timezone'
     or v_payload_source->>'service_day' is distinct from v_source->>'serviceDate'
     or (v_payload_source->>'active_principal_rhythm_count')::integer is distinct from (v_source->>'activePrincipalRhythmCount')::integer
     or (v_payload_source->>'windowed_rhythm_count')::integer is distinct from (v_source->>'windowedRhythmCount')::integer then
    raise exception 'Shadow source binding changed before observation custody.' using errcode='40001';
  end if;
  if v_payload_observed_at > v_current_observed_at
     or v_payload_observed_at < v_current_observed_at - interval '5 minutes' then
    raise exception 'Shadow comparison source observation is too old or from the future.' using errcode='40001';
  end if;
  if jsonb_typeof(v_payload_source->'legacy_windows') <> 'array'
     or jsonb_array_length(v_payload_source->'legacy_windows') <> (v_source->>'activePrincipalRhythmCount')::integer then
    raise exception 'Shadow source window set is incomplete.' using errcode='22023';
  end if;

  for v_rhythm in select value from jsonb_array_elements(v_source->'rhythms') loop
    select count(*)::integer into v_match_count
    from jsonb_array_elements(v_payload_source->'legacy_windows') x
    where x->>'rhythm_ref' = 'atlas.household_rhythms:' || (v_rhythm->>'rhythmId')
      and (x->>'window_start')::timestamptz = (v_rhythm->>'windowStart')::timestamptz
      and (x->>'window_end')::timestamptz = (v_rhythm->>'windowEnd')::timestamptz
      and x->>'principal_ref' = 'atlas.principals:' || v_principal_id::text;
    if v_match_count <> 1 then
      raise exception 'Shadow source windows changed before observation custody.' using errcode='40001';
    end if;
  end loop;

  if v_comparison->'coordinates'->>'principal_ref' <> 'atlas.principals:' || v_principal_id::text
     or v_comparison->'coordinates'->>'service_day' is distinct from v_payload_source->>'service_day'
     or (v_comparison->'coordinates'->>'as_of')::timestamptz is distinct from v_payload_observed_at then
    raise exception 'Comparison coordinate does not match the source observation.' using errcode='22023';
  end if;
  if jsonb_typeof(v_comparison->'observations') <> 'array' then
    raise exception 'Comparison observations must be an array.' using errcode='22023';
  end if;

  select count(*)::integer,
         count(distinct x->>'rhythm_ref')::integer,
         count(*) filter (where x->>'disposition'='equivalent')::integer,
         count(*) filter (where x->>'disposition'='divergent')::integer,
         count(*) filter (where x->>'disposition'='incomplete')::integer
  into v_observation_count,v_distinct_observation_count,v_equivalent_count,v_divergent_count,v_incomplete_count
  from jsonb_array_elements(v_comparison->'observations') x;

  if v_observation_count <> (v_source->>'activePrincipalRhythmCount')::integer
     or v_distinct_observation_count <> v_observation_count
     or v_equivalent_count + v_divergent_count + v_incomplete_count <> v_observation_count then
    raise exception 'Comparison observation inventory does not match the source inventory.' using errcode='22023';
  end if;
  v_expected_state := case when v_divergent_count > 0 then 'divergent' when v_incomplete_count > 0 then 'incomplete' else 'equivalent' end;
  if v_comparison->>'state' <> v_expected_state
     or (v_comparison->>'observation_count')::integer <> v_observation_count
     or (v_comparison->>'equivalent_count')::integer <> v_equivalent_count
     or (v_comparison->>'divergent_count')::integer <> v_divergent_count
     or (v_comparison->>'incomplete_count')::integer <> v_incomplete_count then
    raise exception 'Comparison aggregate state is inconsistent with observations.' using errcode='22023';
  end if;

  for v_rhythm in select value from jsonb_array_elements(v_source->'rhythms') loop
    select count(*)::integer into v_match_count
    from jsonb_array_elements(v_comparison->'observations') o
    where o->>'rhythm_ref' = 'atlas.household_rhythms:' || (v_rhythm->>'rhythmId')
      and (o->'legacy_window'->>'starts_at')::timestamptz = (v_rhythm->>'windowStart')::timestamptz
      and (o->'legacy_window'->>'ends_at')::timestamptz = (v_rhythm->>'windowEnd')::timestamptz
      and o->>'disposition' in ('equivalent','divergent','incomplete')
      and jsonb_typeof(o->'reason_codes')='array';
    if v_match_count <> 1 then
      raise exception 'Comparison does not preserve the live legacy window evidence.' using errcode='22023';
    end if;
  end loop;

  if exists (
    select 1 from jsonb_array_elements(v_comparison->'observations') o
    where o->>'disposition'='equivalent'
      and (
        jsonb_array_length(o->'reason_codes') <> 1
        or o->'reason_codes'->>0 <> 'EQUIVALENT'
        or o->'query_window' is null
        or (o->'query_window'->>'starts_at')::timestamptz is distinct from (o->'legacy_window'->>'starts_at')::timestamptz
        or (o->'query_window'->>'ends_at')::timestamptz is distinct from (o->'legacy_window'->>'ends_at')::timestamptz
      )
  ) then
    raise exception 'Equivalent comparison observations must structurally agree.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rhythmId',r->>'rhythmId',
    'windowStart',(r->>'windowStart')::timestamptz,
    'windowEnd',(r->>'windowEnd')::timestamptz
  ) order by r->>'rhythmId'),'[]'::jsonb)
  into v_source_windows
  from jsonb_array_elements(v_source->'rhythms') r;

  v_source_basis := jsonb_build_object(
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'timezone',v_source->>'timezone',
    'activePrincipalRhythmCount',(v_source->>'activePrincipalRhythmCount')::integer,
    'windowedRhythmCount',(v_source->>'windowedRhythmCount')::integer,
    'rhythms',v_source_windows
  );

  select jsonb_build_object(
    'state',v_comparison->>'state',
    'observations',coalesce(jsonb_agg(jsonb_build_object(
      'rhythmRef',o->>'rhythm_ref',
      'disposition',o->>'disposition',
      'reasonCodes',o->'reason_codes',
      'legacyWindow',o->'legacy_window',
      'queryWindow',o->'query_window'
    ) order by o->>'rhythm_ref'),'[]'::jsonb)
  )
  into v_comparison_basis
  from jsonb_array_elements(v_comparison->'observations') o;

  v_source_fingerprint := encode(extensions.digest(v_source_basis::text,'sha256'),'hex');
  v_comparison_fingerprint := encode(extensions.digest(v_comparison_basis::text,'sha256'),'hex');
  v_source_key := 'household-rhythm-shadow:' || v_baseline_ref || ':' || v_carrier_version || ':' || v_source_fingerprint || ':' || v_comparison_fingerprint;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
    source_kind,source_key,actor_user_id,value,confidence,observed_at,
    effective_from,effective_until,provenance,metadata
  ) values (
    'principal',v_principal_id,'atlas_migration','household_rhythm_shadow',v_household_id::text,
    'shadow_comparison_observation','household_rhythm_shadow_carrier',v_source_key,v_user_id,
    jsonb_build_object(
      'contractVersion','household_rhythm_shadow_observation_evidence_v1',
      'baselineRef',v_baseline_ref,
      'sourceState',v_source_basis,
      'comparison',v_comparison_basis
    ),
    null,v_payload_observed_at,null,null,
    jsonb_build_object(
      'baselineVersion',v_baseline_version,
      'carrierVersion',v_carrier_version,
      'serverVersion',v_server_version,
      'sourceReadContract','household_rhythm_shadow_state_self_api_v1',
      'custodyContract','household_rhythm_shadow_observation_custody_v1',
      'sourceStateFingerprint',v_source_fingerprint,
      'comparisonFingerprint',v_comparison_fingerprint,
      'recomputationRequiredForReliance',true
    ),
    jsonb_build_object(
      'canonicalAuthority',false,
      'claimCreated',false,
      'retirementAuthority',false,
      'repairAuthority',false,
      'cutoverAnchorAuthority',false,
      'comparisonReceiptIsDerivedEvidence',true
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_evidence_id;

  if v_evidence_id is null then
    select * into v_existing
    from atlas.evidence_records e
    where e.scope_kind='principal' and e.scope_id=v_principal_id
      and e.source_kind='household_rhythm_shadow_carrier' and e.source_key=v_source_key;
    if v_existing.id is null
       or v_existing.evidence_kind is distinct from 'shadow_comparison_observation'
       or v_existing.subject_domain is distinct from 'atlas_migration'
       or v_existing.subject_kind is distinct from 'household_rhythm_shadow'
       or v_existing.subject_id is distinct from v_household_id::text then
      raise exception 'Shadow observation evidence identity conflict.' using errcode='23505';
    end if;
    v_evidence_id := v_existing.id;
  else
    v_created := true;
  end if;

  return jsonb_build_object(
    'contractVersion','household_rhythm_shadow_observation_custody_v1',
    'ok',true,
    'created',v_created,
    'deduplicated',not v_created,
    'evidenceId',v_evidence_id,
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'observedAt',v_payload_observed_at,
    'comparisonState',v_expected_state,
    'sourceStateFingerprint',v_source_fingerprint,
    'comparisonFingerprint',v_comparison_fingerprint,
    'truthBoundary',jsonb_build_object(
      'evidenceOnly',true,
      'claimCreated',false,
      'canonicalRealityChanged',false,
      'householdRhythmAuthorityChanged',false,
      'cutoverAnchorRebased',false,
      'retirementAuthorized',false,
      'divergenceRepaired',false
    )
  );
end;
$function$;

revoke all on function atlas.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from public;
revoke all on function atlas.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from anon;
revoke all on function atlas.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from authenticated;

create or replace function atlas.household_rhythm_shadow_observation_history_self_api_v1(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_limit integer := greatest(1,least(coalesce(p_limit,100),500));
  v_rows jsonb;
begin
  if v_user_id is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object('contractVersion','household_rhythm_shadow_observation_history_self_api_v1','state','principal_required','observations','[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(x.row_data order by x.learned_at desc,x.id desc),'[]'::jsonb)
  into v_rows
  from (
    select e.learned_at,e.id,jsonb_build_object(
      'evidenceId',e.id,
      'observedAt',e.observed_at,
      'learnedAt',e.learned_at,
      'sourceKey',e.source_key,
      'value',e.value,
      'provenance',e.provenance,
      'metadata',e.metadata
    ) as row_data
    from atlas.evidence_records e
    where e.scope_kind='principal' and e.scope_id=v_principal_id
      and e.subject_domain='atlas_migration' and e.subject_kind='household_rhythm_shadow'
      and e.evidence_kind='shadow_comparison_observation'
      and e.source_kind='household_rhythm_shadow_carrier'
    order by e.learned_at desc,e.id desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'contractVersion','household_rhythm_shadow_observation_history_self_api_v1',
    'state','ready',
    'principalId',v_principal_id,
    'observations',v_rows,
    'truthBoundary',jsonb_build_object(
      'evidenceOnly',true,
      'historyCreatesAuthority',false,
      'historyAuthorizesRetirement',false,
      'recomputationRequiredForReliance',true
    )
  );
end;
$function$;

revoke all on function atlas.household_rhythm_shadow_observation_history_self_api_v1(integer) from public;
revoke all on function atlas.household_rhythm_shadow_observation_history_self_api_v1(integer) from anon;
revoke all on function atlas.household_rhythm_shadow_observation_history_self_api_v1(integer) from authenticated;

create or replace function public.record_household_rhythm_shadow_observation_self_api_v1(p_payload jsonb)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select atlas.record_household_rhythm_shadow_observation_self_api_v1(p_payload);
$function$;
revoke all on function public.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from public;
revoke all on function public.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from anon;
revoke all on function public.record_household_rhythm_shadow_observation_self_api_v1(jsonb) from authenticated;
grant execute on function public.record_household_rhythm_shadow_observation_self_api_v1(jsonb) to authenticated;

create or replace function public.household_rhythm_shadow_observation_history_self_api_v1(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select atlas.household_rhythm_shadow_observation_history_self_api_v1(p_limit);
$function$;
revoke all on function public.household_rhythm_shadow_observation_history_self_api_v1(integer) from public;
revoke all on function public.household_rhythm_shadow_observation_history_self_api_v1(integer) from anon;
revoke all on function public.household_rhythm_shadow_observation_history_self_api_v1(integer) from authenticated;
grant execute on function public.household_rhythm_shadow_observation_history_self_api_v1(integer) to authenticated;
