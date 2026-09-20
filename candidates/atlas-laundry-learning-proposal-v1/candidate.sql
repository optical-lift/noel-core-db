begin;

-- Laundry Learning Proposal v1.
--
-- Repeated physical actuals may support a proposal. They never silently create
-- an accepted household Rhythm or other durable operating truth.

create or replace function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_instance atlas.household_kernel_instances%rowtype;
  v_dates date[];
  v_claim_ids uuid[];
  v_evidence_ids uuid[];
  v_dows integer[];
  v_gaps integer[];
  v_support_count integer;
  v_same_weekday boolean;
  v_gaps_stable boolean;
  v_weekday integer;
  v_weekday_name text;
  v_proposal_value jsonb;
  v_analysis_value jsonb;
  v_source_key text;
  v_analysis_evidence_id uuid;
  v_proposal_claim_id uuid;
  v_existing_claim_id uuid;
  v_created boolean := false;
  v_idx integer;
  v_existing_value jsonb;
  v_existing_analysis jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  v_household_id := atlas.principal_current_household_id_v1();

  if v_principal_id is null or v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  v_timezone := atlas.principal_authoritative_timezone_v1(v_principal_id);

  select *
  into v_instance
  from atlas.household_kernel_instances i
  where i.household_id=v_household_id
    and i.kernel_key='household.laundry'
    and i.state='active'
  limit 1;

  if v_instance.id is null then
    raise exception 'Active Laundry instance required before learning patterns.'
      using errcode='42501';
  end if;

  with actuals as (
    select
      c.id as claim_id,
      e.id as evidence_id,
      e.observed_at,
      (e.observed_at at time zone v_timezone)::date as local_date,
      extract(dow from (e.observed_at at time zone v_timezone)::date)::integer as local_dow,
      row_number() over (
        partition by (e.observed_at at time zone v_timezone)::date
        order by e.observed_at,e.id
      ) as within_day_rank
    from atlas.claim_records c
    join atlas.evidence_records e on e.id=c.primary_evidence_id
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type='process_actual'
      and c.lifecycle_state='observed'
      and c.authority_kind='household_principal_observation'
      and c.value->>'transition'='entered_washing'
      and c.value->>'toState'='washing'
      and e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.subject_domain='household.laundry'
      and e.subject_kind='kernel_instance'
      and e.subject_id=v_instance.id::text
      and e.evidence_kind='physical_process_actual'
      and e.provenance->>'actualContract'='personal_laundry_process_actual_v1'
      and e.observed_at is not null
  ), distinct_dates as (
    select claim_id,evidence_id,observed_at,local_date,local_dow
    from actuals
    where within_day_rank=1
    order by local_date desc
    limit 4
  ), ordered as (
    select *
    from distinct_dates
    order by local_date
  )
  select
    array_agg(local_date order by local_date),
    array_agg(claim_id order by local_date),
    array_agg(evidence_id order by local_date),
    array_agg(local_dow order by local_date),
    count(*)::integer
  into
    v_dates,
    v_claim_ids,
    v_evidence_ids,
    v_dows,
    v_support_count
  from ordered;

  if coalesce(v_support_count,0)<4 then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','insufficient_evidence',
      'supportCount',coalesce(v_support_count,0),
      'requiredDistinctDates',4,
      'proposalCreated',false,
      'truthBoundary',jsonb_build_object(
        'learningDoesNotGuessFromSparseEvidence',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_same_weekday :=
    v_dows[1]=v_dows[2]
    and v_dows[2]=v_dows[3]
    and v_dows[3]=v_dows[4];

  v_gaps := array[
    (v_dates[2]-v_dates[1])::integer,
    (v_dates[3]-v_dates[2])::integer,
    (v_dates[4]-v_dates[3])::integer
  ];

  v_gaps_stable :=
    v_gaps[1] between 6 and 8
    and v_gaps[2] between 6 and 8
    and v_gaps[3] between 6 and 8;

  if not v_same_weekday or not v_gaps_stable then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','pattern_not_stable',
      'supportCount',v_support_count,
      'localDates',to_jsonb(v_dates),
      'localWeekdays',to_jsonb(v_dows),
      'gapDays',to_jsonb(v_gaps),
      'proposalCreated',false,
      'truthBoundary',jsonb_build_object(
        'nonmatchingActualsRemainActuals',true,
        'learningDoesNotForcePattern',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_weekday := v_dows[1];
  v_weekday_name := trim(to_char(v_dates[1],'Day'));

  v_proposal_value := jsonb_build_object(
    'patternKind','weekly',
    'proposedLocalWeekday',v_weekday,
    'proposedLocalWeekdayName',v_weekday_name,
    'basisTransition','entered_washing',
    'cadenceToleranceDays',jsonb_build_array(6,8)
  );

  v_analysis_value := jsonb_build_object(
    'analysisContract','personal_laundry_weekly_pattern_learning_v1',
    'timezone',v_timezone,
    'instanceId',v_instance.id,
    'basisTransition','entered_washing',
    'localDates',to_jsonb(v_dates),
    'localWeekdays',to_jsonb(v_dows),
    'gapDays',to_jsonb(v_gaps),
    'actualClaimIds',to_jsonb(v_claim_ids),
    'actualEvidenceIds',to_jsonb(v_evidence_ids),
    'result',v_proposal_value
  );

  -- If the same proposal is already awaiting adjudication, do not create a
  -- duplicate prompt. Attach any newly selected actual Evidence as support.
  select c.id
  into v_existing_claim_id
  from atlas.claim_records c
  where c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=v_instance.id::text
    and c.claim_type='rhythm_pattern_proposal'
    and c.lifecycle_state='proposed'
    and c.authority_kind='derived_pattern_proposal'
    and c.value=v_proposal_value
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_existing_claim_id is not null then
    for v_idx in 1..array_length(v_evidence_ids,1)
    loop
      insert into atlas.claim_evidence_links(
        claim_id,evidence_id,relation_kind,metadata
      ) values (
        v_existing_claim_id,
        v_evidence_ids[v_idx],
        'supports',
        jsonb_build_object(
          'supportRole','physical_actual',
          'actualClaimId',v_claim_ids[v_idx],
          'learningContract','personal_laundry_weekly_pattern_learning_v1'
        )
      )
      on conflict do nothing;
    end loop;

    return jsonb_build_object(
      'ok',true,
      'contractVersion','personal_laundry_weekly_pattern_learning_v1',
      'state','already_proposed',
      'proposalCreated',false,
      'proposalClaimId',v_existing_claim_id,
      'proposal',v_proposal_value,
      'supportActualClaimIds',to_jsonb(v_claim_ids),
      'truthBoundary',jsonb_build_object(
        'additionalEvidenceMayStrengthenProposal',true,
        'proposalValueWasNotSilentlyChanged',true,
        'proposalStillRequiresAdjudication',true,
        'doesNotCreateRhythm',true
      )
    );
  end if;

  v_source_key :=
    'household.laundry:weekly_pattern:'
    ||v_instance.id::text||':'
    ||array_to_string(v_claim_ids,':');

  insert into atlas.evidence_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    evidence_kind,
    source_kind,
    source_key,
    actor_user_id,
    value,
    confidence,
    observed_at,
    learned_at,
    provenance,
    metadata
  ) values (
    'household',
    v_household_id,
    'household.laundry',
    'kernel_instance',
    v_instance.id::text,
    'derived_pattern_analysis',
    'household_learning_engine',
    v_source_key,
    null,
    v_analysis_value,
    null,
    null,
    now(),
    jsonb_build_object(
      'learningContract','personal_laundry_weekly_pattern_learning_v1',
      'derivedFromActualEvidenceIds',to_jsonb(v_evidence_ids),
      'derivedFromActualClaimIds',to_jsonb(v_claim_ids)
    ),
    jsonb_build_object(
      'proposalAuthority',false,
      'acceptedTruthAuthority',false,
      'rhythmAuthority',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_analysis_evidence_id;

  if v_analysis_evidence_id is null then
    select e.id,e.value
    into v_analysis_evidence_id,v_existing_analysis
    from atlas.evidence_records e
    where e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.source_kind='household_learning_engine'
      and e.source_key=v_source_key
      and e.subject_domain='household.laundry'
      and e.subject_kind='kernel_instance'
      and e.subject_id=v_instance.id::text
      and e.evidence_kind='derived_pattern_analysis';

    if v_analysis_evidence_id is null
       or v_existing_analysis is distinct from v_analysis_value then
      raise exception 'Laundry learning sourceKey retry does not match existing analysis Evidence.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_records(
    scope_kind,
    scope_id,
    subject_domain,
    subject_kind,
    subject_id,
    claim_type,
    lifecycle_state,
    authority_kind,
    source_kind,
    source_key,
    value,
    confidence,
    primary_evidence_id,
    metadata
  ) values (
    'household',
    v_household_id,
    'household.laundry',
    'kernel_instance',
    v_instance.id::text,
    'rhythm_pattern_proposal',
    'proposed',
    'derived_pattern_proposal',
    'household_learning_engine',
    v_source_key,
    v_proposal_value,
    null,
    v_analysis_evidence_id,
    jsonb_build_object(
      'learningContract','personal_laundry_weekly_pattern_learning_v1',
      'requiresHumanOrGovernedAdjudication',true,
      'materializesRhythm',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning id into v_proposal_claim_id;

  if v_proposal_claim_id is not null then
    v_created := true;
  else
    select c.id,c.value
    into v_proposal_claim_id,v_existing_value
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.source_kind='household_learning_engine'
      and c.source_key=v_source_key
      and c.subject_domain='household.laundry'
      and c.subject_kind='kernel_instance'
      and c.subject_id=v_instance.id::text
      and c.claim_type='rhythm_pattern_proposal'
      and c.lifecycle_state='proposed'
      and c.authority_kind='derived_pattern_proposal';

    if v_proposal_claim_id is null
       or v_existing_value is distinct from v_proposal_value then
      raise exception 'Laundry learning sourceKey retry does not match existing proposed Claim.'
        using errcode='23505';
    end if;
  end if;

  insert into atlas.claim_evidence_links(
    claim_id,evidence_id,relation_kind,metadata
  ) values (
    v_proposal_claim_id,
    v_analysis_evidence_id,
    'supports',
    jsonb_build_object(
      'primary',true,
      'supportRole','derived_analysis',
      'learningContract','personal_laundry_weekly_pattern_learning_v1'
    )
  )
  on conflict do nothing;

  for v_idx in 1..array_length(v_evidence_ids,1)
  loop
    insert into atlas.claim_evidence_links(
      claim_id,evidence_id,relation_kind,metadata
    ) values (
      v_proposal_claim_id,
      v_evidence_ids[v_idx],
      'supports',
      jsonb_build_object(
        'supportRole','physical_actual',
        'actualClaimId',v_claim_ids[v_idx],
        'learningContract','personal_laundry_weekly_pattern_learning_v1'
      )
    )
    on conflict do nothing;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_laundry_weekly_pattern_learning_v1',
    'state','proposed',
    'proposalCreated',v_created,
    'proposalClaimId',v_proposal_claim_id,
    'analysisEvidenceId',v_analysis_evidence_id,
    'proposal',v_proposal_value,
    'supportActualClaimIds',to_jsonb(v_claim_ids),
    'supportActualEvidenceIds',to_jsonb(v_evidence_ids),
    'truthBoundary',jsonb_build_object(
      'actualsRemainSourceTruth',true,
      'patternIsProposalNotAcceptedTruth',true,
      'proposalAuthorityIsDerivedNotPrincipalAuthored',true,
      'proposalRequiresAdjudication',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateTask',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1() is
  'Conservative Laundry learner. Four distinct entered_washing dates on the same Principal-local weekday with 6-8 day adjacent gaps may create a derived Household rhythm-pattern proposal with all supporting actual Evidence linked. Never accepts or materializes a Rhythm.';

revoke all on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
  from public, anon;
grant execute on function atlas.propose_personal_laundry_weekly_pattern_self_api_v1()
  to authenticated, service_role;


insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values (
  'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Analyze source-backed Laundry cycle-start actuals and, only under the narrow deterministic V1 rule, create or reinforce a derived weekly-pattern proposal.',
    'authorizationBoundary','SECURITY DEFINER fixes current Household and Laundry instance to auth-bound Principal custody. Fewer than four distinct dates, mixed weekdays, or gaps outside 6-8 days create no proposal. Any output Claim remains proposed with derived authority and never materializes Rhythm.',
    'directSignedInEndpoint',true
  ),
  now(),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;
