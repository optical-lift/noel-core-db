-- Candidate only: never run directly on production.
-- Dependencies (not production-live as of 2026-10-15):
--   20260910054000_atlas_personal_cleaning_spaces_object_care_v1
--   atlas.record_current_household_claim_evidence_api_v1(jsonb) candidate.
--
-- One explicitly reported physical action on ONE confirmed household object.
-- Does not claim that the room is restored or that a Today occurrence is complete.
begin;

create or replace function atlas.record_personal_cleaning_object_actual_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_household_id uuid;
  v_source_key text;
  v_object_id uuid;
  v_requirement_id uuid;
  v_capture_id uuid;
  v_capture atlas.personal_reality_captures%rowtype;
  v_object atlas.household_care_objects%rowtype;
  v_requirement atlas.household_object_care_requirements%rowtype;
  v_transition text;
  v_occurrence timestamptz;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'A Cleaning actual input object is required.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_input) k(key)
      where k.key not in ('sourceActionId','objectId','requirementId','transition','occurredAt','captureId')) then
    raise exception 'Cleaning actual accepts only its defined identity, physical event, time, and optional source capture.'
      using errcode='22023';
  end if;
  v_source_key:=nullif(btrim(p_input->>'sourceActionId'),'');
  v_transition:=nullif(btrim(p_input->>'transition'),'');
  if v_source_key is null or length(v_source_key)>200 then
    raise exception 'A bounded sourceActionId is required.' using errcode='22023';
  end if;
  if v_transition not in ('care_performed','care_partially_performed','care_blocked') then
    raise exception 'Unsupported Cleaning actual transition.' using errcode='22023';
  end if;
  if not atlas.personal_reality_timestamp_is_explicit_v1(p_input->>'occurredAt') then
    raise exception 'A physical Cleaning actual requires an explicit offset-aware occurrence time.'
      using errcode='22023';
  end if;
  begin
    v_occurrence:=(p_input->>'occurredAt')::timestamptz;
    v_object_id:=nullif(p_input->>'objectId','')::uuid;
    v_requirement_id:=nullif(p_input->>'requirementId','')::uuid;
    v_capture_id:=nullif(p_input->>'captureId','')::uuid;
  exception when others then
    raise exception 'Cleaning actual identifiers or occurrence time are invalid.'
      using errcode='22023';
  end;
  if v_object_id is null or v_requirement_id is null or v_occurrence is null then
    raise exception 'Specific object, requirement, and physical occurrence time are required.'
      using errcode='22023';
  end if;

  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then
    raise exception 'Active Principal Household required.' using errcode='42501';
  end if;
  select * into v_object
  from atlas.household_care_objects o
  where o.id=v_object_id and o.household_id=v_household_id
    and o.active and o.confidence='confirmed'
  for key share;
  if v_object.id is null then
    raise exception 'Confirmed care object not established for the current Household.'
      using errcode='42501';
  end if;
  select * into v_requirement
  from atlas.household_object_care_requirements r
  where r.id=v_requirement_id and r.object_id=v_object.id
    and r.household_id=v_household_id and r.active and r.care_kind='cleaning'
  for key share;
  if v_requirement.id is null then
    raise exception 'Active Cleaning requirement not established for that object.'
      using errcode='42501';
  end if;

  if v_capture_id is not null then
    select * into v_capture
    from atlas.personal_reality_captures c
    where c.id=v_capture_id and c.owner_user_id=v_user_id
      and c.principal_id=atlas.current_principal_id_v1();
    if v_capture.id is null then
      raise exception 'Source testimony does not belong to this Principal.'
        using errcode='42501';
    end if;
  end if;

  -- This writer uses the existing household Evidence/Claim membrane. Its
  -- idempotent source identity is STABLE ACROSS RETRIES, independent of transition;
  -- a changed transition using the same identity must be rejected by that membrane.
  v_result:=atlas.record_current_household_claim_evidence_api_v1(
    jsonb_build_object(
      'sourceKey','household.cleaning.object.actual:'||v_source_key,
      'subject',jsonb_build_object(
        'domain','household.cleaning',
        'kind','care_object',
        'id',v_object.id::text
      ),
      'evidence',jsonb_build_object(
        'kind','first_party_physical_care_actual',
        'value',jsonb_build_object(
          'requirementId',v_requirement.id,
          'transition',v_transition
        ),
        'confidence',1,
        'observedAt',v_occurrence,
        'provenance',jsonb_strip_nulls(jsonb_build_object(
          'sourceActionId',v_source_key,
          'optionalPersonalRealityCaptureId',v_capture_id,
          'optionalCaptureEvidenceId',v_capture.evidence_id,
          'actualContract','household_object_care_actual_v1'
        ))
      ),
      'claim',jsonb_build_object(
        'claimType','care_actual',
        'lifecycleState','observed',
        'value',jsonb_build_object(
          'requirementId',v_requirement.id,
          'transition',v_transition
        ),
        'confidence',1,
        'validFrom',v_occurrence,
        'metadata',jsonb_build_object(
          'actualContract','household_object_care_actual_v1',
          'physicalActionIsFirstPartyReported',true,
          'roomConditionNotInferred',true
        )
      )
    )
  );
  if coalesce((v_result->>'ok')::boolean,false) is not true
      or nullif(v_result->>'claimId','') is null
      or nullif(v_result->>'evidenceId','') is null then
    raise exception 'Household care physical actual did not return confirmed source identities.'
      using errcode='55000';
  end if;

  return v_result||jsonb_build_object(
    'contractVersion','household_object_care_actual_v1',
    'householdId',v_household_id,
    'objectId',v_object.id,
    'requirementId',v_requirement.id,
    'transition',v_transition,
    'occurredAt',v_occurrence,
    'truthBoundary',jsonb_build_object(
      'firstPartyPhysicalActual',true,
      'notWholeRoomRestoration',true,
      'notTaskCompletion',true,
      'notAutomaticRecurrenceResolution',true,
      'notClockPlacement',true
    )
  );
end;
$function$;

comment on function atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb) is
  'Record one explicitly confirmed physical Cleaning action on one source-owned object and requirement, using current Household Evidence/Claim authority; never infer whole-room recovery or task completion.';

revoke all on function atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)
  from public,anon;
grant execute on function atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)
  to authenticated,service_role;

create or replace function public.record_personal_cleaning_object_actual_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.record_personal_cleaning_object_actual_self_api_v1(p_input);
$function$;

revoke all on function public.record_personal_cleaning_object_actual_self_api_v1(jsonb)
  from public,anon;
grant execute on function public.record_personal_cleaning_object_actual_self_api_v1(jsonb)
  to authenticated,service_role;


-- A narrow re-read for exactly one owner-scoped physical actual. Do not expose
-- the entire Household Claim/Evidence ledger just to verify a single action.
create or replace function atlas.personal_cleaning_object_actual_self_api_v1(p_claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_claim atlas.claim_records%rowtype;
  v_evidence atlas.evidence_records%rowtype;
  v_requirement_id uuid;
  v_transition text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null or p_claim_id is null then
    raise exception 'Current Household and exact actual Claim required.' using errcode='42501';
  end if;
  select c.* into v_claim
    from atlas.claim_records c
    join atlas.household_care_objects o
      on o.id::text=c.subject_id
     and o.household_id=c.scope_id
    where c.id=p_claim_id
      and c.scope_kind='household'
      and c.scope_id=v_household_id
      and c.subject_domain='household.cleaning'
      and c.subject_kind='care_object'
      and c.claim_type='care_actual'
      and c.lifecycle_state='observed'
      and c.source_kind='household_principal_capture'
      and o.household_id=v_household_id;
  if v_claim.id is null then
    raise exception 'A current-household Cleaning object actual was not found.' using errcode='P0002';
  end if;
  select e.* into v_evidence
    from atlas.evidence_records e
    where e.id=v_claim.primary_evidence_id
      and e.scope_kind='household'
      and e.scope_id=v_household_id
      and e.subject_domain=v_claim.subject_domain
      and e.subject_kind=v_claim.subject_kind
      and e.subject_id=v_claim.subject_id
      and e.source_kind=v_claim.source_kind
      and e.source_key=v_claim.source_key
      and e.evidence_kind='first_party_physical_care_actual'
      and e.actor_user_id=auth.uid();
  if v_evidence.id is null
     or v_evidence.value is distinct from v_claim.value
     or v_evidence.observed_at is distinct from v_claim.valid_from then
    raise exception 'Physical actual Claim/Evidence identity mismatch.' using errcode='55000';
  end if;
  v_requirement_id:=nullif(v_claim.value->>'requirementId','')::uuid;
  v_transition:=v_claim.value->>'transition';
  if v_requirement_id is null
    or v_transition not in ('care_performed','care_partially_performed','care_blocked')
    or not exists(
      select 1 from atlas.household_object_care_requirements r
      where r.id=v_requirement_id
        and r.object_id::text=v_claim.subject_id
        and r.household_id=v_household_id
        and r.care_kind='cleaning'
    ) then
    raise exception 'Physical actual requirement/transition cannot be verified.' using errcode='55000';
  end if;
  return jsonb_build_object(
    'ok',true,
    'contractVersion','household_object_care_actual_read_v1',
    'householdId',v_household_id,
    'objectId',v_claim.subject_id,
    'requirementId',v_requirement_id,
    'claimId',v_claim.id,
    'evidenceId',v_evidence.id,
    'transition',v_transition,
    'occurredAt',v_evidence.observed_at,
    'actorUserId',v_evidence.actor_user_id,
    'truthBoundary',jsonb_build_object(
      'ownerScopedVerifiedPhysicalReport',true,
      'fullRoomConditionNotEstablished',true,
      'requirementOccurrenceNotResolved',true,
      'noClockPlacement',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_object_actual_self_api_v1(uuid) from public,anon;
grant execute on function atlas.personal_cleaning_object_actual_self_api_v1(uuid)
  to authenticated,service_role;

create or replace function public.personal_cleaning_object_actual_self_api_v1(p_claim_id uuid)
returns jsonb
language sql stable security definer set search_path=pg_catalog
as $function$
  select atlas.personal_cleaning_object_actual_self_api_v1(p_claim_id);
$function$;

revoke all on function public.personal_cleaning_object_actual_self_api_v1(uuid) from public,anon;
grant execute on function public.personal_cleaning_object_actual_self_api_v1(uuid)
  to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values (
  'atlas.record_personal_cleaning_object_actual_self_api_v1(jsonb)',
  'app_endpoint','verified','active',
  true,true,true,false,0,0,
  jsonb_build_object(
    'purpose','Record an explicitly reported object-level physical Cleaning action through the current Household Claim/Evidence membrane.',
    'boundary','No implicit room condition, task completion, future recurrence, or Clock placement; scope and exact object/requirement derived or checked on the server.'
  ),now()
),(
  'atlas.personal_cleaning_object_actual_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,true,false,0,0,
  jsonb_build_object(
    'purpose','Narrow owner-scoped read-back of one object Cleaning physical actual with Claim/Evidence identity and requirement proof.',
    'boundary','Only one current-Household exact Claim; verifies primary Evidence, actor, requirement identity and supported physical transition.'
  ),now()
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();

commit;
