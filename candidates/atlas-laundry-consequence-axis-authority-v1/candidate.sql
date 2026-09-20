begin;

-- Laundry Consequence Axis Authority v1.
--
-- Requirement, carrier, execution readiness, and Clock placement are distinct
-- authorities. This candidate binds Household responsibility/readiness Claims
-- to the carrier/readiness axes and preserves them across later requirement
-- re-evaluation.

create or replace function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
  p_owner_user_id uuid,
  p_definition_id uuid,
  p_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_principal_id uuid;
  v_household_id uuid;
  v_definition atlas.person_life_definitions%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_mode text;
begin
  if p_owner_user_id is null or p_definition_id is null or p_claim_id is null then
    raise exception 'owner user, definition id, and responsibility Claim id are required.'
      using errcode='22023';
  end if;

  select p.id,h.id
  into v_principal_id,v_household_id
  from atlas.principals p
  join atlas.households h on h.principal_id=p.id
  where p.user_id=p_owner_user_id
    and p.status='active'
    and h.status='active'
  order by
    case when p.active_household_id=h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;

  if v_principal_id is null or v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=p_owner_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Active Laundry consequence definition not found for this owner.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.id=p_claim_id
    and c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=v_definition.subject_id
    and c.claim_type='ordinary_responsibility'
    and c.lifecycle_state='accepted'
    and c.authority_kind in (
      'household_principal_acceptance',
      'household_principal_correction'
    );

  if v_claim.id is null then
    raise exception 'Current accepted same-instance Laundry ordinary_responsibility Claim required.'
      using errcode='42501';
  end if;

  v_mode := nullif(btrim(v_claim.value->>'mode'),'');

  if v_mode not in (
    'self',
    'shared',
    'other_household_member',
    'outside_household',
    'service',
    'unresolved',
    'other'
  ) then
    raise exception 'Laundry responsibility Claim has unsupported mode.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'claimId',v_claim.id,
    'mode',v_mode,
    'carrierRef',case
      when v_mode='self' then 'principal:'||v_principal_id::text
      else null
    end,
    'carrierState',case
      when v_mode='self' then 'established'
      else 'unresolved'
    end,
    'truthBoundary',jsonb_build_object(
      'selfMayResolvePrincipalCarrier',true,
      'sharedDoesNotMeanPrincipal',true,
      'otherModesDoNotInventCarrierIdentity',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid) is
  'Internal deterministic carrier resolution from one accepted current-Household Laundry ordinary_responsibility Claim. V1 resolves self to the active Principal and leaves all other modes unresolved.';

revoke all on function atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.personal_laundry_execution_readiness_from_claim_v1(
  p_owner_user_id uuid,
  p_definition_id uuid,
  p_claim_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_household_id uuid;
  v_definition atlas.person_life_definitions%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_state text;
begin
  if p_owner_user_id is null or p_definition_id is null or p_claim_id is null then
    raise exception 'owner user, definition id, and readiness Claim id are required.'
      using errcode='22023';
  end if;

  select h.id
  into v_household_id
  from atlas.households h
  join atlas.principals p on p.id=h.principal_id
  where p.user_id=p_owner_user_id
    and p.status='active'
    and h.status='active'
  order by
    case when p.active_household_id=h.id then 0 else 1 end,
    h.created_at,
    h.id
  limit 1;

  if v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=p_owner_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Active Laundry consequence definition not found for this owner.'
      using errcode='42501';
  end if;

  select *
  into v_claim
  from atlas.claim_records c
  where c.id=p_claim_id
    and c.scope_kind='household'
    and c.scope_id=v_household_id
    and c.subject_domain='household.laundry'
    and c.subject_kind='kernel_instance'
    and c.subject_id=v_definition.subject_id
    and c.claim_type='execution_readiness'
    and c.lifecycle_state in ('observed','accepted')
    and c.authority_kind in (
      'household_principal_observation',
      'household_principal_acceptance',
      'household_principal_correction'
    );

  if v_claim.id is null then
    raise exception 'Current same-instance Laundry execution_readiness Claim required.'
      using errcode='42501';
  end if;

  v_state := nullif(btrim(v_claim.value->>'state'),'');

  if v_state not in ('ready','blocked','unknown') then
    raise exception 'Laundry execution_readiness Claim has unsupported state.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'claimId',v_claim.id,
    'state',v_state,
    'executionReadiness',case
      when v_state='ready' then 'ready'
      when v_state='blocked' then 'blocked'
      else 'not_evaluated'
    end,
    'truthBoundary',jsonb_build_object(
      'requirementExistenceIsSeparate',true,
      'blockedDoesNotDeleteRequirement',true,
      'unknownDoesNotBecomeReady',true
    )
  );
end;
$$;

comment on function atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid) is
  'Internal deterministic execution-readiness resolution from one current-Household Laundry execution_readiness Claim. ready/blocked/unknown map to ready/blocked/not_evaluated without affecting requirement truth.';

revoke all on function atlas.personal_laundry_execution_readiness_from_claim_v1(uuid,uuid,uuid)
  from public, anon, authenticated, service_role;


create or replace function atlas.guard_personal_laundry_consequence_axis_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_definition atlas.person_life_definitions%rowtype;
  v_carrier_authority jsonb;
  v_old_carrier_authority jsonb;
  v_readiness_authority jsonb;
  v_old_readiness_authority jsonb;
  v_claim_id uuid;
  v_resolution jsonb;
  v_expected_carrier_ref text;
  v_expected_carrier_state text;
  v_expected_readiness text;
begin
  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=new.definition_id;

  if v_definition.id is null
     or v_definition.subject_domain<>'household.laundry'
     or v_definition.subject_kind<>'kernel_instance' then
    return new;
  end if;

  v_carrier_authority := new.evidence->'carrierAuthority';
  v_old_carrier_authority := old.evidence->'carrierAuthority';

  if new.carrier_ref is distinct from old.carrier_ref
     or new.carrier_state is distinct from old.carrier_state then

    if jsonb_typeof(v_carrier_authority)='object'
       and nullif(v_carrier_authority->>'claimId','') is not null then
      begin
        v_claim_id := (v_carrier_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Laundry consequence carrier authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      v_expected_carrier_ref := nullif(v_resolution->>'carrierRef','');
      v_expected_carrier_state := v_resolution->>'carrierState';

      if new.carrier_ref is distinct from v_expected_carrier_ref
         or new.carrier_state is distinct from v_expected_carrier_state then
        raise exception 'Laundry consequence carrier fields must equal the source-backed responsibility resolution.'
          using errcode='23514';
      end if;

    elsif jsonb_typeof(v_old_carrier_authority)='object'
          and nullif(v_old_carrier_authority->>'claimId','') is not null then
      -- A requirement refresh has no carrier authority. Revalidate the old
      -- source Claim before preserving the separately established axis.
      begin
        v_claim_id := (v_old_carrier_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Stored Laundry carrier authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      if old.carrier_ref is distinct from nullif(v_resolution->>'carrierRef','')
         or old.carrier_state is distinct from v_resolution->>'carrierState' then
        raise exception 'Stored Laundry carrier projection no longer matches its source authority.'
          using errcode='23514';
      end if;

      new.carrier_ref := old.carrier_ref;
      new.carrier_state := old.carrier_state;
      new.evidence := coalesce(new.evidence,'{}'::jsonb)
        || jsonb_build_object('carrierAuthority',v_old_carrier_authority);

    elsif new.carrier_ref is not null or new.carrier_state<>'unresolved' then
      raise exception 'Laundry consequence carrier cannot be established without authorized responsibility Claim evidence.'
        using errcode='23514';
    end if;

  elsif jsonb_typeof(v_old_carrier_authority)='object'
        and jsonb_typeof(v_carrier_authority)<>'object' then
    begin
      v_claim_id := (v_old_carrier_authority->>'claimId')::uuid;
    exception when invalid_text_representation then
      raise exception 'Stored Laundry carrier authority Claim id is invalid.'
        using errcode='23514';
    end;

    v_resolution :=
      atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
        new.owner_user_id,
        new.definition_id,
        v_claim_id
      );

    if old.carrier_ref is distinct from nullif(v_resolution->>'carrierRef','')
       or old.carrier_state is distinct from v_resolution->>'carrierState' then
      raise exception 'Stored Laundry carrier projection no longer matches its source authority.'
        using errcode='23514';
    end if;

    new.evidence := coalesce(new.evidence,'{}'::jsonb)
      || jsonb_build_object('carrierAuthority',v_old_carrier_authority);
  end if;

  v_readiness_authority := new.evidence->'readinessAuthority';
  v_old_readiness_authority := old.evidence->'readinessAuthority';

  if new.execution_readiness is distinct from old.execution_readiness then

    if jsonb_typeof(v_readiness_authority)='object'
       and nullif(v_readiness_authority->>'claimId','') is not null then
      begin
        v_claim_id := (v_readiness_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Laundry consequence readiness authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_execution_readiness_from_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      v_expected_readiness := v_resolution->>'executionReadiness';

      if new.execution_readiness is distinct from v_expected_readiness then
        raise exception 'Laundry consequence execution readiness must equal the source-backed readiness resolution.'
          using errcode='23514';
      end if;

    elsif jsonb_typeof(v_old_readiness_authority)='object'
          and nullif(v_old_readiness_authority->>'claimId','') is not null then
      -- A requirement refresh has no readiness authority. Revalidate the old
      -- source Claim before preserving the independently established axis.
      begin
        v_claim_id := (v_old_readiness_authority->>'claimId')::uuid;
      exception when invalid_text_representation then
        raise exception 'Stored Laundry readiness authority Claim id is invalid.'
          using errcode='23514';
      end;

      v_resolution :=
        atlas.personal_laundry_execution_readiness_from_claim_v1(
          new.owner_user_id,
          new.definition_id,
          v_claim_id
        );

      if old.execution_readiness is distinct from v_resolution->>'executionReadiness' then
        raise exception 'Stored Laundry readiness projection no longer matches its source authority.'
          using errcode='23514';
      end if;

      new.execution_readiness := old.execution_readiness;
      new.evidence := coalesce(new.evidence,'{}'::jsonb)
        || jsonb_build_object('readinessAuthority',v_old_readiness_authority);

    elsif new.execution_readiness<>'not_evaluated' then
      raise exception 'Laundry consequence execution readiness cannot change without authorized readiness Claim evidence.'
        using errcode='23514';
    end if;

  elsif jsonb_typeof(v_old_readiness_authority)='object'
        and jsonb_typeof(v_readiness_authority)<>'object' then
    begin
      v_claim_id := (v_old_readiness_authority->>'claimId')::uuid;
    exception when invalid_text_representation then
      raise exception 'Stored Laundry readiness authority Claim id is invalid.'
        using errcode='23514';
    end;

    v_resolution :=
      atlas.personal_laundry_execution_readiness_from_claim_v1(
        new.owner_user_id,
        new.definition_id,
        v_claim_id
      );

    if old.execution_readiness is distinct from v_resolution->>'executionReadiness' then
      raise exception 'Stored Laundry readiness projection no longer matches its source authority.'
        using errcode='23514';
    end if;

    new.evidence := coalesce(new.evidence,'{}'::jsonb)
      || jsonb_build_object('readinessAuthority',v_old_readiness_authority);
  end if;

  -- Placement is intentionally outside this authority.
  if new.placement_state is distinct from old.placement_state then
    raise exception 'Laundry consequence placement state is owned by a later Clock authority, not carrier/readiness reconciliation.'
      using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_personal_laundry_consequence_axis_authority_v1() is
  'Protect Laundry Person Life consequence carrier/readiness axes from unauthorized mutation and from erasure during later requirement re-evaluation. Placement remains outside this authority.';

revoke all on function atlas.guard_personal_laundry_consequence_axis_authority_v1()
  from public, anon, authenticated, service_role;

drop trigger if exists person_life_laundry_consequence_axis_guard_v1
  on atlas.person_life_consequence_instances;

create trigger person_life_laundry_consequence_axis_guard_v1
before update on atlas.person_life_consequence_instances
for each row
execute function atlas.guard_personal_laundry_consequence_axis_authority_v1();


create or replace function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(
  p_consequence_instance_id uuid,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_instance atlas.person_life_consequence_instances%rowtype;
  v_definition atlas.person_life_definitions%rowtype;
  v_responsibility_claim_id uuid;
  v_readiness_claim_id uuid;
  v_carrier_resolution jsonb;
  v_readiness_resolution jsonb;
  v_new_carrier_ref text;
  v_new_carrier_state text;
  v_new_readiness text;
  v_new_evidence jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_consequence_instance_id is null
     or p_input is null
     or jsonb_typeof(p_input)<>'object' then
    raise exception 'consequenceInstanceId and reconciliation input object are required.'
      using errcode='22023';
  end if;

  begin
    v_responsibility_claim_id :=
      nullif(p_input->>'responsibilityClaimId','')::uuid;
    v_readiness_claim_id :=
      nullif(p_input->>'readinessClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'responsibilityClaimId and readinessClaimId must be UUIDs when supplied.'
      using errcode='22023';
  end;

  if v_responsibility_claim_id is null and v_readiness_claim_id is null then
    raise exception 'At least one responsibilityClaimId or readinessClaimId is required.'
      using errcode='22023';
  end if;

  if (select count(*) from jsonb_object_keys(p_input)) <>
     (case when v_responsibility_claim_id is null then 0 else 1 end
      + case when v_readiness_claim_id is null then 0 else 1 end) then
    raise exception 'Unsupported Laundry consequence reconciliation field.'
      using errcode='22023';
  end if;

  select i.*
  into v_instance
  from atlas.person_life_consequence_instances i
  where i.id=p_consequence_instance_id
    and i.owner_user_id=v_user_id
    and i.status='open';

  if v_instance.id is null then
    raise exception 'Open Laundry consequence not found for the signed-in user.'
      using errcode='42501';
  end if;

  select *
  into v_definition
  from atlas.person_life_definitions d
  where d.id=v_instance.definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.subject_domain='household.laundry'
    and d.subject_kind='kernel_instance';

  if v_definition.id is null then
    raise exception 'Open consequence is not governed by an active Laundry consequence definition.'
      using errcode='42501';
  end if;

  v_new_carrier_ref := v_instance.carrier_ref;
  v_new_carrier_state := v_instance.carrier_state;
  v_new_readiness := v_instance.execution_readiness;
  v_new_evidence := coalesce(v_instance.evidence,'{}'::jsonb);

  if v_responsibility_claim_id is not null then
    v_carrier_resolution :=
      atlas.personal_laundry_carrier_resolution_from_responsibility_claim_v1(
        v_user_id,
        v_instance.definition_id,
        v_responsibility_claim_id
      );

    v_new_carrier_ref := nullif(v_carrier_resolution->>'carrierRef','');
    v_new_carrier_state := v_carrier_resolution->>'carrierState';

    v_new_evidence := v_new_evidence || jsonb_build_object(
      'carrierAuthority',
      jsonb_build_object(
        'claimId',v_responsibility_claim_id,
        'mode',v_carrier_resolution->>'mode',
        'carrierRef',v_new_carrier_ref,
        'carrierState',v_new_carrier_state,
        'resolutionContract','personal_laundry_carrier_resolution_from_responsibility_claim_v1'
      )
    );
  end if;

  if v_readiness_claim_id is not null then
    v_readiness_resolution :=
      atlas.personal_laundry_execution_readiness_from_claim_v1(
        v_user_id,
        v_instance.definition_id,
        v_readiness_claim_id
      );

    v_new_readiness := v_readiness_resolution->>'executionReadiness';

    v_new_evidence := v_new_evidence || jsonb_build_object(
      'readinessAuthority',
      jsonb_build_object(
        'claimId',v_readiness_claim_id,
        'state',v_readiness_resolution->>'state',
        'executionReadiness',v_new_readiness,
        'resolutionContract','personal_laundry_execution_readiness_from_claim_v1'
      )
    );
  end if;

  update atlas.person_life_consequence_instances i
  set carrier_ref=v_new_carrier_ref,
      carrier_state=v_new_carrier_state,
      execution_readiness=v_new_readiness,
      evidence=v_new_evidence,
      updated_at=now()
  where i.id=v_instance.id
    and i.owner_user_id=v_user_id
  returning * into v_instance;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_laundry_consequence_axis_reconciliation_v1',
    'consequence',to_jsonb(v_instance),
    'clockAdmission',
      atlas.person_life_consequence_clock_admission_state_v1(
        v_user_id,
        v_instance.id
      ),
    'truthBoundary',jsonb_build_object(
      'requirementAuthorityUnchanged',true,
      'carrierAuthorityComesOnlyFromResponsibilityClaim',true,
      'readinessAuthorityComesOnlyFromReadinessClaim',true,
      'blockedDoesNotDeleteRequirement',true,
      'placementAuthorityUnchanged',true,
      'doesNotCreateTask',true,
      'doesNotCreateClockCandidate',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb) is
  'Reconcile carrier and/or execution-readiness axes of one owned open Laundry Person Life consequence from explicit current-Household Claims. Requirement and placement authorities are unchanged.';

revoke all on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)
  from public, anon;
grant execute on function atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(uuid,jsonb)
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
  'atlas.reconcile_personal_laundry_consequence_axes_self_api_v1(p_consequence_instance_id uuid, p_input jsonb)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Reconcile Laundry consequence carrier/readiness from explicit same-instance current-Household Claims while preserving requirement and placement authority.',
    'authorizationBoundary','SECURITY DEFINER fixes ownership to auth.uid(); carrier derives only from accepted ordinary_responsibility Claim and readiness only from observed/accepted execution_readiness Claim; caller cannot submit axis values directly.',
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
  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after Laundry consequence axis authority registration.';
  end if;
end
$$;

commit;
