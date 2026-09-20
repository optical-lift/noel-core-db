begin;

-- Personal Reality -> Household Claim Route v1
--
-- Raw spontaneous testimony remains in person custody.
-- A human-confirmed Household interpretation receives new same-subject
-- Household interpretation Evidence and a Household Claim.
-- Cross-scope Claim/Evidence links remain prohibited.

create or replace function atlas.guard_personal_reality_household_claim_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  if new.scope_kind='person'
     and new.source_kind='personal_reality_claim'
     and (new.subject_domain='household' or new.subject_domain like 'household.%') then
    raise exception 'Personal Reality Household claims must use the Household application route, not person Claim custody.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_reality_household_claim_scope_v1() is
  'Fail-closed guard preventing the legacy person-Claim Personal Reality route from storing Household-subject claims in person custody.';

revoke all on function atlas.guard_personal_reality_household_claim_scope_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists personal_reality_household_claim_scope_guard_v1
  on atlas.claim_records;

create trigger personal_reality_household_claim_scope_guard_v1
before insert or update on atlas.claim_records
for each row
execute function atlas.guard_personal_reality_household_claim_scope_v1();


create or replace function atlas.record_current_household_claim_from_capture_evidence_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_raw_evidence_id uuid;
  v_proposal_id uuid;
  v_receipt_id uuid;
  v_supersedes_claim_id uuid;
  v_subject jsonb;
  v_claim jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_claim_type text;
  v_lifecycle text;
  v_authority text;
  v_confidence numeric;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_metadata jsonb;
  v_source_key text;
  v_raw atlas.evidence_records%rowtype;
  v_old atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_existing_claim atlas.claim_records%rowtype;
  v_evidence_id uuid;
  v_claim_id uuid;
  v_created boolean := false;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Household capture-claim input must be an object.' using errcode='22023';
  end if;

  begin
    v_raw_evidence_id := nullif(p_input->>'sourceEvidenceId','')::uuid;
    v_proposal_id := nullif(p_input->>'proposalId','')::uuid;
    v_receipt_id := nullif(p_input->>'decisionReceiptId','')::uuid;
    v_supersedes_claim_id := nullif(p_input->>'supersedesClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'sourceEvidenceId, proposalId, decisionReceiptId, and supersedesClaimId must be UUID values when supplied.'
      using errcode='22023';
  end;

  v_subject := p_input->'subject';
  v_claim := p_input->'claim';

  if v_raw_evidence_id is null
     or v_proposal_id is null
     or v_receipt_id is null
     or jsonb_typeof(v_subject)<>'object'
     or jsonb_typeof(v_claim)<>'object' then
    raise exception 'sourceEvidenceId, proposalId, decisionReceiptId, subject, and claim are required.'
      using errcode='22023';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select * into v_raw
  from atlas.evidence_records e
  where e.id=v_raw_evidence_id
    and e.scope_kind='person'
    and e.scope_id=v_user_id
    and e.source_kind='personal_reality_capture';

  if v_raw.id is null then
    raise exception 'Source Evidence must be the signed-in person Personal Reality capture Evidence.'
      using errcode='42501';
  end if;

  if not exists (
    select 1
    from atlas.personal_reality_human_decision_receipts r
    where r.id=v_receipt_id
      and r.proposal_id=v_proposal_id
      and r.owner_user_id=v_user_id
      and r.decision='confirm'
      and r.consumed_at is not null
  ) then
    raise exception 'Consumed human confirmation receipt required.'
      using errcode='42501';
  end if;

  v_subject_domain := nullif(btrim(v_subject->>'domain'),'');
  v_subject_kind := nullif(btrim(v_subject->>'kind'),'');
  v_subject_id := nullif(btrim(v_subject->>'id'),'');
  v_claim_type := nullif(btrim(v_claim->>'claimType'),'');
  v_lifecycle := nullif(btrim(v_claim->>'lifecycleState'),'');

  if v_subject_domain is null
     or v_subject_kind is null
     or v_subject_id is null
     or v_claim_type is null
     or v_lifecycle is null
     or not (v_claim ? 'value') then
    raise exception 'Resolved Household subject and complete claim are required.'
      using errcode='22023';
  end if;

  if v_subject_domain<>'household'
     and v_subject_domain not like 'household.%' then
    raise exception 'Household Personal Reality route accepts only household subjects.'
      using errcode='22023';
  end if;

  if v_lifecycle not in ('reported','observed','accepted','rejected','unknown') then
    raise exception 'Unsupported human-confirmed Household claim lifecycle.'
      using errcode='22023';
  end if;

  if v_claim ? 'confidence' then
    v_confidence := (v_claim->>'confidence')::numeric;
    if v_confidence<0 or v_confidence>1 then
      raise exception 'claim confidence must be 0..1.' using errcode='22023';
    end if;
  end if;

  begin
    v_valid_from := nullif(v_claim->>'validFrom','')::timestamptz;
    v_valid_until := nullif(v_claim->>'validUntil','')::timestamptz;
  exception when others then
    raise exception 'Household claim validity timestamps are invalid.'
      using errcode='22023';
  end;

  if v_valid_from is not null
     and v_valid_until is not null
     and v_valid_until<v_valid_from then
    raise exception 'validUntil precedes validFrom.' using errcode='22023';
  end if;

  v_metadata := coalesce(
    case when jsonb_typeof(v_claim->'metadata')='object' then v_claim->'metadata' end,
    '{}'::jsonb
  );

  v_source_key := 'personal_reality_household_proposal:'||v_proposal_id::text;

  if v_supersedes_claim_id is not null then
    select * into v_old
    from atlas.claim_records c
    where c.id=v_supersedes_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain=v_subject_domain
      and c.subject_kind=v_subject_kind
      and c.subject_id=v_subject_id;

    if v_old.id is null then
      raise exception 'supersedesClaimId must identify the same-subject Claim in the current Principal Household.'
        using errcode='42501';
    end if;
  end if;

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
    effective_from,
    effective_until,
    provenance,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    'human_confirmed_interpretation',
    'personal_reality_household_claim_interpretation',
    v_source_key,
    v_user_id,
    v_claim->'value',
    1,
    v_raw.observed_at,
    v_valid_from,
    v_valid_until,
    jsonb_build_object(
      'sourceEvidenceId',v_raw_evidence_id,
      'sourceEvidenceScope','person',
      'proposalId',v_proposal_id,
      'decisionReceiptId',v_receipt_id,
      'crossScopePromotion',true
    ),
    jsonb_build_object(
      'rawTestimonyNotCopied',true,
      'crossScopeClaimEvidenceLinkCreated',false
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning * into v_evidence;

  if v_evidence.id is null then
    select * into v_evidence
    from atlas.evidence_records e
    where e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.source_kind='personal_reality_household_claim_interpretation'
      and e.source_key=v_source_key;

    if v_evidence.id is null
       or v_evidence.subject_domain is distinct from v_subject_domain
       or v_evidence.subject_kind is distinct from v_subject_kind
       or v_evidence.subject_id is distinct from v_subject_id
       or v_evidence.value is distinct from v_claim->'value'
       or v_evidence.observed_at is distinct from v_raw.observed_at
       or v_evidence.effective_from is distinct from v_valid_from
       or v_evidence.effective_until is distinct from v_valid_until
       or v_evidence.provenance is distinct from jsonb_build_object(
         'sourceEvidenceId',v_raw_evidence_id,
         'sourceEvidenceScope','person',
         'proposalId',v_proposal_id,
         'decisionReceiptId',v_receipt_id,
         'crossScopePromotion',true
       ) then
      raise exception 'Proposal retry does not match Household interpretation Evidence.'
        using errcode='23505';
    end if;
  end if;

  v_evidence_id := v_evidence.id;

  v_authority := case
    when v_supersedes_claim_id is not null then 'household_principal_correction'
    when v_lifecycle='observed' then 'household_principal_observation'
    when v_lifecycle='accepted' then 'household_principal_acceptance'
    when v_lifecycle='rejected' then 'household_principal_rejection'
    when v_lifecycle='reported' then 'household_principal_report'
    else 'household_principal_confirmed_interpretation'
  end;

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
    supersedes_claim_id,
    valid_from,
    valid_until,
    metadata
  ) values (
    'household',
    v_household_id,
    v_subject_domain,
    v_subject_kind,
    v_subject_id,
    v_claim_type,
    v_lifecycle,
    v_authority,
    'personal_reality_household_claim',
    v_source_key,
    v_claim->'value',
    v_confidence,
    v_evidence_id,
    v_supersedes_claim_id,
    v_valid_from,
    v_valid_until,
    v_metadata || jsonb_build_object(
      'sourceEvidenceId',v_raw_evidence_id,
      'sourceEvidenceScope','person',
      'proposalId',v_proposal_id,
      'decisionReceiptId',v_receipt_id
    )
  )
  on conflict(scope_kind,scope_id,source_kind,source_key) do nothing
  returning * into v_existing_claim;

  if v_existing_claim.id is null then
    select * into v_existing_claim
    from atlas.claim_records c
    where c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.source_kind='personal_reality_household_claim'
      and c.source_key=v_source_key;

    if v_existing_claim.id is null
       or v_existing_claim.subject_domain is distinct from v_subject_domain
       or v_existing_claim.subject_kind is distinct from v_subject_kind
       or v_existing_claim.subject_id is distinct from v_subject_id
       or v_existing_claim.claim_type is distinct from v_claim_type
       or v_existing_claim.lifecycle_state is distinct from v_lifecycle
       or v_existing_claim.authority_kind is distinct from v_authority
       or v_existing_claim.value is distinct from v_claim->'value'
       or v_existing_claim.confidence is distinct from v_confidence
       or v_existing_claim.primary_evidence_id is distinct from v_evidence_id
       or v_existing_claim.supersedes_claim_id is distinct from v_supersedes_claim_id
       or v_existing_claim.valid_from is distinct from v_valid_from
       or v_existing_claim.valid_until is distinct from v_valid_until then
      raise exception 'Proposal retry does not match Household Claim.'
        using errcode='23505';
    end if;
  else
    v_created := true;
  end if;

  v_claim_id := v_existing_claim.id;

  insert into atlas.claim_evidence_links(
    claim_id,evidence_id,relation_kind,metadata
  ) values (
    v_claim_id,
    v_evidence_id,
    'supports',
    jsonb_build_object('primary',true,'custodyScope','household')
  )
  on conflict do nothing;

  -- The raw Evidence is person-scoped and therefore is intentionally not
  -- inserted into claim_evidence_links. Provenance above retains the source id.
  if v_created and v_supersedes_claim_id is not null then
    update atlas.claim_records c
    set lifecycle_state='superseded',
        superseded_at=now()
    where c.id=v_supersedes_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.lifecycle_state<>'superseded';

    if not found then
      raise exception 'Household Claim being corrected was already superseded.'
        using errcode='23505';
    end if;

    insert into atlas.claim_evidence_links(
      claim_id,evidence_id,relation_kind,metadata
    ) values (
      v_supersedes_claim_id,
      v_evidence_id,
      'corrects',
      jsonb_build_object(
        'correctedByClaimId',v_claim_id,
        'rawSourceEvidenceId',v_raw_evidence_id,
        'rawSourceEvidenceScope','person'
      )
    )
    on conflict do nothing;
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created,
    'scope',jsonb_build_object('kind','household','id',v_household_id),
    'claimId',v_claim_id,
    'interpretationEvidenceId',v_evidence_id,
    'sourceEvidenceId',v_raw_evidence_id,
    'truthBoundary',jsonb_build_object(
      'rawEvidenceRemainsPersonScoped',true,
      'rawTestimonyCopied',false,
      'rawEvidenceReferencedByProvenance',true,
      'crossScopeClaimEvidenceLinkCreated',false,
      'householdInterpretationEvidenceIsPrimary',true,
      'doesNotCreateTask',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateConsequence',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.record_current_household_claim_from_capture_evidence_v1(jsonb) is
  'Internal promotion writer from signed-in person Personal Reality source Evidence + consumed human confirmation into same-subject current-Household interpretation Evidence and Claim. Raw testimony remains person-scoped and is referenced only through provenance; no cross-scope Claim/Evidence link is created.';

revoke all on function atlas.record_current_household_claim_from_capture_evidence_v1(jsonb)
  from public, anon, authenticated, service_role;


create or replace function atlas.apply_personal_reality_household_claim_effect_self_api_v1(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_old_proposal atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_body jsonb;
  v_result jsonb;
  v_old_claim atlas.claim_records%rowtype;
  v_supersedes_claim_id uuid;
  v_old_decision_state text;
  v_old_route_state text;
  v_capture_state text;
  v_route_before text;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_household_id := atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal household required.' using errcode='42501';
  end if;

  select * into v_proposal
  from atlas.personal_reality_effect_proposals p
  where p.id=p_proposal_id
    and p.owner_user_id=v_user_id
  for update;

  if v_proposal.id is null then
    raise exception 'Effect proposal not found.' using errcode='P0002';
  end if;

  select * into v_capture
  from atlas.personal_reality_captures c
  where c.id=v_proposal.capture_id
    and c.owner_user_id=v_user_id;

  if v_capture.id is null then
    raise exception 'Personal Reality capture not found.' using errcode='P0002';
  end if;

  if v_proposal.route_state='applied' then
    return jsonb_build_object(
      'ok',true,
      'changed',false,
      'routeState','applied',
      'destinationKind',v_proposal.destination_kind,
      'destinationId',v_proposal.destination_id,
      'destinationState',atlas.personal_reality_destination_state_v1(
        v_proposal.destination_kind,
        v_proposal.destination_id
      )
    );
  end if;

  if v_proposal.effect_kind<>'claim' then
    raise exception 'Household Personal Reality application route accepts claim effects only.'
      using errcode='22023';
  end if;

  if v_proposal.decision_state<>'confirmed'
     or v_proposal.decision_receipt_id is null then
    raise exception 'Human confirmation receipt required before Household application.'
      using errcode='42501';
  end if;

  if v_proposal.readiness_state<>'ready_for_confirmation'
     or v_proposal.route_state not in ('ready','destination_unavailable') then
    raise exception 'Proposal is not ready for Household application.'
      using errcode='22023';
  end if;

  v_body := v_proposal.proposal;
  v_subject_domain := nullif(btrim(v_body#>>'{subject,domain}'),'');
  v_subject_kind := nullif(btrim(v_body#>>'{subject,kind}'),'');
  v_subject_id := nullif(btrim(v_body#>>'{subject,id}'),'');

  if v_subject_domain is null
     or (v_subject_domain<>'household' and v_subject_domain not like 'household.%') then
    raise exception 'Proposal is not a Household-subject Claim.'
      using errcode='22023';
  end if;

  if v_subject_kind is null or v_subject_id is null then
    raise exception 'Resolved Household subject required.'
      using errcode='22023';
  end if;

  if v_proposal.supersedes_proposal_id is not null then
    select * into v_old_proposal
    from atlas.personal_reality_effect_proposals p
    where p.id=v_proposal.supersedes_proposal_id
      and p.owner_user_id=v_user_id
      and p.principal_id=v_proposal.principal_id
    for update;

    if v_old_proposal.id is null
       or v_old_proposal.effect_kind<>'claim'
       or v_old_proposal.decision_state='revoked'
       or v_old_proposal.route_state='superseded' then
      raise exception 'Superseded Household Claim proposal is unavailable or obsolete.'
        using errcode='23505';
    end if;

    v_old_decision_state := v_old_proposal.decision_state;
    v_old_route_state := v_old_proposal.route_state;

    if v_old_proposal.route_state='applied' then
      begin
        select * into v_old_claim
        from atlas.claim_records c
        where c.id=v_old_proposal.destination_id::uuid
          and c.scope_kind='household'
          and c.scope_id=v_household_id;
      exception when invalid_text_representation then
        raise exception 'Prior Household Claim destination identity is invalid.'
          using errcode='23514';
      end;

      if v_old_claim.id is null then
        raise exception 'Prior Household Claim destination missing.'
          using errcode='P0002';
      end if;

      if v_old_claim.subject_domain is distinct from v_subject_domain
         or v_old_claim.subject_kind is distinct from v_subject_kind
         or v_old_claim.subject_id is distinct from v_subject_id then
        raise exception 'Household Personal Reality correction must remain on the same subject.'
          using errcode='23514';
      end if;

      v_supersedes_claim_id := v_old_claim.id;
    end if;
  end if;

  v_result := atlas.record_current_household_claim_from_capture_evidence_v1(
    jsonb_build_object(
      'sourceEvidenceId',v_capture.evidence_id,
      'proposalId',v_proposal.id,
      'decisionReceiptId',v_proposal.decision_receipt_id,
      'subject',v_body->'subject',
      'claim',v_body->'claim',
      'supersedesClaimId',v_supersedes_claim_id
    )
  );

  v_route_before := v_proposal.route_state;

  update atlas.personal_reality_effect_proposals
  set route_state='applied',
      applied_at=coalesce(applied_at,now()),
      destination_kind='claim_record',
      destination_id=v_result->>'claimId',
      updated_at=now()
  where id=v_proposal.id
  returning * into v_proposal;

  insert into atlas.personal_reality_effect_events(
    proposal_id,
    capture_id,
    principal_id,
    actor_user_id,
    authority_receipt_id,
    event_kind,
    state_axis,
    from_state,
    to_state,
    detail
  ) values (
    v_proposal.id,
    v_capture.id,
    v_capture.principal_id,
    v_user_id,
    v_proposal.decision_receipt_id,
    'applied',
    'route',
    v_route_before,
    'applied',
    jsonb_build_object(
      'destinationKind','claim_record',
      'destinationId',v_proposal.destination_id,
      'destinationScope','household',
      'sourceEvidenceId',v_capture.evidence_id
    )
  );

  if v_old_proposal.id is not null then
    update atlas.personal_reality_effect_proposals
    set decision_state='revoked',
        route_state=case
          when route_state='applied' then 'superseded'
          else 'not_ready'
        end,
        revoked_at=now(),
        updated_at=now()
    where id=v_old_proposal.id
    returning * into v_old_proposal;

    insert into atlas.personal_reality_effect_events(
      proposal_id,
      capture_id,
      principal_id,
      actor_user_id,
      authority_receipt_id,
      event_kind,
      state_axis,
      from_state,
      to_state,
      detail
    ) values (
      v_old_proposal.id,
      v_old_proposal.capture_id,
      v_old_proposal.principal_id,
      v_user_id,
      v_proposal.decision_receipt_id,
      'superseded',
      'decision',
      v_old_decision_state,
      'revoked',
      jsonb_build_object(
        'supersededByProposalId',v_proposal.id,
        'oldDestinationReversed',v_supersedes_claim_id is not null
      )
    );

    if v_old_route_state is distinct from v_old_proposal.route_state then
      insert into atlas.personal_reality_effect_events(
        proposal_id,
        capture_id,
        principal_id,
        actor_user_id,
        authority_receipt_id,
        event_kind,
        state_axis,
        from_state,
        to_state,
        detail
      ) values (
        v_old_proposal.id,
        v_old_proposal.capture_id,
        v_old_proposal.principal_id,
        v_user_id,
        v_proposal.decision_receipt_id,
        'superseded',
        'route',
        v_old_route_state,
        v_old_proposal.route_state,
        jsonb_build_object('supersededByProposalId',v_proposal.id)
      );
    end if;

    perform atlas.refresh_personal_reality_capture_state_v1(
      v_old_proposal.capture_id
    );
  end if;

  v_capture_state := atlas.refresh_personal_reality_capture_state_v1(
    v_capture.id
  );

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','personal_reality_household_claim_application_v1',
    'proposalId',v_proposal.id,
    'decisionState',v_proposal.decision_state,
    'routeState',v_proposal.route_state,
    'effectKind',v_proposal.effect_kind,
    'destinationKind',v_proposal.destination_kind,
    'destinationId',v_proposal.destination_id,
    'destinationScope','household',
    'destinationState',atlas.personal_reality_destination_state_v1(
      v_proposal.destination_kind,
      v_proposal.destination_id
    ),
    'sourceEvidenceId',v_capture.evidence_id,
    'interpretationEvidenceId',v_result->>'interpretationEvidenceId',
    'captureState',v_capture_state,
    'truthBoundary',jsonb_build_object(
      'applicationAuthorityComesFromHumanDecisionReceiptNotCaller',true,
      'rawTestimonyRemainsPersonScoped',true,
      'householdInterpretationEvidenceCreated',true,
      'crossScopeClaimEvidenceLinkCreated',false,
      'correctionIsSameSubjectAndTransactional',true,
      'doesNotCreateTask',true,
      'doesNotCreateRhythm',true,
      'doesNotCreateConsequence',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid) is
  'Apply an already-human-confirmed Personal Reality claim proposal whose resolved subject belongs to the current Principal Household. Raw testimony remains person-scoped; same-subject Household interpretation Evidence and Claim are created transactionally.';

revoke all on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  from public, anon;
grant execute on function atlas.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  to authenticated, service_role;


create or replace function public.apply_personal_reality_household_claim_effect_self_api_v1(
  p_proposal_id uuid
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select atlas.apply_personal_reality_household_claim_effect_self_api_v1(p_proposal_id);
$$;

revoke all on function public.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
  from public, anon;
grant execute on function public.apply_personal_reality_household_claim_effect_self_api_v1(uuid)
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
  'atlas.apply_personal_reality_household_claim_effect_self_api_v1(p_proposal_id uuid)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Apply an already-confirmed Personal Reality claim proposal into current-Household Claim/Evidence custody.',
    'authorizationBoundary','SECURITY DEFINER derives Household from auth.uid(), requires the existing consumed human confirmation receipt, accepts Household subjects only, preserves raw testimony in person custody, and grants no task/Rhythm/consequence/carrier/Clock authority.',
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

do $$
begin
  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
  ) then
    raise exception 'Authenticated RPC registry drifted after Household Personal Reality claim route registration.';
  end if;
end
$$;

commit;
