-- Canonical Personal Atlas household residence arrangement + first Reality Discovery promotion adapter.
--
-- This table owns the durable relationship: this household resides at this place/address, with the
-- explicitly supplied tenure and major-repair responsibility. It does not own building systems,
-- property title, tax liability, or a universal Place ontology.

create table if not exists atlas.household_residence_arrangements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  stable_key text not null,
  dwelling_id uuid references atlas.dwellings(id) on delete set null,
  address jsonb,
  tenure_kind text check (tenure_kind is null or tenure_kind in ('own','rent','family_provided','other')),
  major_repairs_responsibility text check (major_repairs_responsibility is null or major_repairs_responsibility in ('me','shared','landlord','depends')),
  active boolean not null default true,
  source_kind text not null,
  source_ref text,
  confidence text not null default 'confirmed' check (confidence in ('candidate','confirmed')),
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(household_id,stable_key)
);

create index if not exists household_residence_arrangements_household_active_idx
  on atlas.household_residence_arrangements(household_id,active);

alter table atlas.household_residence_arrangements enable row level security;
revoke all on atlas.household_residence_arrangements from public,anon,authenticated;

create or replace function atlas.upsert_personal_residence_arrangement_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_household_id uuid;
  v_stable_key text;
  v_address jsonb;
  v_tenure text;
  v_repairs text;
  v_source_kind text;
  v_source_ref text;
  v_row atlas.household_residence_arrangements%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Residence input must be an object.' using errcode='22023'; end if;

  v_stable_key:=coalesce(nullif(trim(p_input->>'stableKey'),''),'primary-home');
  v_address:=p_input->'address';
  v_tenure:=nullif(trim(p_input->>'tenureKind'),'');
  v_repairs:=nullif(trim(p_input->>'majorRepairsResponsibility'),'');
  v_source_kind:=coalesce(nullif(trim(p_input->>'sourceKind'),''),'personal_atlas');
  v_source_ref:=nullif(trim(p_input->>'sourceRef'),'');

  if v_address is not null and jsonb_typeof(v_address)<>'object' then
    raise exception 'Residence address must be an object when supplied.' using errcode='22023';
  end if;
  if v_tenure is not null and v_tenure not in ('own','rent','family_provided','other') then
    raise exception 'Unsupported tenure kind.' using errcode='22023';
  end if;
  if v_repairs is not null and v_repairs not in ('me','shared','landlord','depends') then
    raise exception 'Unsupported major-repair responsibility.' using errcode='22023';
  end if;

  insert into atlas.household_residence_arrangements(
    household_id,stable_key,address,tenure_kind,major_repairs_responsibility,
    active,source_kind,source_ref,confidence,confirmed_at,metadata
  ) values(
    v_household_id,v_stable_key,v_address,v_tenure,v_repairs,
    true,v_source_kind,v_source_ref,'confirmed',now(),
    jsonb_build_object('lastConfirmedByUserId',v_user_id)
  )
  on conflict(household_id,stable_key) do update set
    address=coalesce(excluded.address,atlas.household_residence_arrangements.address),
    tenure_kind=coalesce(excluded.tenure_kind,atlas.household_residence_arrangements.tenure_kind),
    major_repairs_responsibility=coalesce(excluded.major_repairs_responsibility,atlas.household_residence_arrangements.major_repairs_responsibility),
    active=true,
    source_kind=excluded.source_kind,
    source_ref=coalesce(excluded.source_ref,atlas.household_residence_arrangements.source_ref),
    confidence='confirmed',
    confirmed_at=now(),
    metadata=coalesce(atlas.household_residence_arrangements.metadata,'{}'::jsonb)||excluded.metadata,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_residence_arrangement_v1',
    'residence',jsonb_build_object(
      'id',v_row.id,
      'stableKey',v_row.stable_key,
      'address',v_row.address,
      'tenureKind',v_row.tenure_kind,
      'majorRepairsResponsibility',v_row.major_repairs_responsibility,
      'confidence',v_row.confidence,
      'confirmedAt',v_row.confirmed_at
    ),
    'truthBoundary',jsonb_build_object(
      'residenceArrangementIsCanonical',true,
      'propertyTitleNotClaimed',true,
      'taxLiabilityNotClaimed',true,
      'buildingSystemsNotClaimed',true
    )
  );
end;
$function$;

create or replace function atlas.personal_residence_arrangement_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_row atlas.household_residence_arrangements%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  select * into v_row
  from atlas.household_residence_arrangements
  where household_id=v_household_id and active
  order by case when stable_key='primary-home' then 0 else 1 end,confirmed_at desc nulls last,id
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_residence_arrangement_self_api_v1',
    'residence',case when v_row.id is null then null else jsonb_build_object(
      'id',v_row.id,'stableKey',v_row.stable_key,'address',v_row.address,
      'tenureKind',v_row.tenure_kind,'majorRepairsResponsibility',v_row.major_repairs_responsibility,
      'confidence',v_row.confidence,'confirmedAt',v_row.confirmed_at
    ) end
  );
end;
$function$;

revoke all on function atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.personal_residence_arrangement_self_api_v1() from public,anon;
grant execute on function atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.personal_residence_arrangement_self_api_v1() to authenticated,service_role;

create or replace function public.upsert_personal_residence_arrangement_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.upsert_personal_residence_arrangement_self_api_v1(p_input); $function$;
create or replace function public.personal_residence_arrangement_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_residence_arrangement_self_api_v1(); $function$;

revoke all on function public.upsert_personal_residence_arrangement_self_api_v1(jsonb) from public,anon;
revoke all on function public.personal_residence_arrangement_self_api_v1() from public,anon;
grant execute on function public.upsert_personal_residence_arrangement_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.personal_residence_arrangement_self_api_v1() to authenticated,service_role;

-- Extend the Discovery context to prefer canonical residence truth once promoted.
create or replace function atlas.reality_discovery_context_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_residence atlas.household_residence_arrangements%rowtype;
  v_member_count integer:=0;
  v_child_count integer:=0;
  v_answers jsonb:='{}'::jsonb;
  v_candidates jsonb:='{}'::jsonb;
  v_signals jsonb:='{}'::jsonb;
  v_purchase_address jsonb;
  v_purchase_phone jsonb;
  v_tenure text;
  v_repairs text;
  v_grounds text;
  v_mowing text;
  v_vehicle_count text;
  v_address_confirmed boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  select * into v_household from atlas.households where id=v_principal.active_household_id and status='active';

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where claimed_by_user_id=v_user_id and claimed_principal_id=v_principal.id
  order by purchased_at desc,id desc limit 1;

  select * into v_residence
  from atlas.household_residence_arrangements
  where household_id=v_household.id and active
  order by case when stable_key='primary-home' then 0 else 1 end,confirmed_at desc nulls last,id
  limit 1;

  v_purchase_address:=case
    when v_purchase.metadata ? 'billingAddress' and v_purchase.metadata->'billingAddress' <> 'null'::jsonb
      then v_purchase.metadata->'billingAddress'
    else null
  end;
  v_purchase_phone:=case
    when nullif(trim(v_purchase.metadata->>'phone'),'') is not null then to_jsonb(trim(v_purchase.metadata->>'phone'))
    else null
  end;

  select count(*)::integer,
         count(*) filter(where lower(coalesce(relationship,'')) in ('child','son','daughter'))::integer
  into v_member_count,v_child_count
  from atlas.household_members
  where household_id=v_household.id and active;

  v_answers:=atlas.reality_discovery_latest_answers_v1(v_principal.id);

  select coalesce(jsonb_object_agg(signal_key,candidate_value),'{}'::jsonb)
  into v_candidates
  from (
    select distinct on(signal_key) signal_key,candidate_value
    from atlas.reality_discovery_evidence_candidates
    where principal_id=v_principal.id and epistemic_state in ('source_candidate','human_confirmed','promoted')
    order by signal_key,
      case epistemic_state when 'promoted' then 1 when 'human_confirmed' then 2 else 3 end,
      updated_at desc,id desc
  ) c;

  if v_purchase_address is not null then v_candidates:=v_candidates||jsonb_build_object('purchase.billing_address',v_purchase_address); end if;
  if v_purchase_phone is not null then v_candidates:=v_candidates||jsonb_build_object('purchase.phone',v_purchase_phone); end if;

  v_address_confirmed:=v_residence.id is not null and v_residence.address is not null;
  v_tenure:=coalesce(v_residence.tenure_kind,v_answers#>>'{home.tenure}');
  v_repairs:=coalesce(v_residence.major_repairs_responsibility,v_answers#>>'{home.major_repairs}');
  v_grounds:=v_answers#>>'{grounds.responsibility}';
  v_mowing:=v_answers#>>'{grounds.mowing_method}';
  v_vehicle_count:=v_answers#>>'{transport.vehicle_count}';

  v_signals:=jsonb_build_object(
    'principal.exists',true,
    'household.exists',v_household.id is not null,
    'household.member_count',v_member_count,
    'household.member_count_bucket',case when v_member_count<=1 then 'one' when v_member_count<=3 then 'small' else 'large' end,
    'household.has_children',v_child_count>0,
    'household.child_count',v_child_count,
    'home.address_confirmed',v_address_confirmed,
    'home.tenure',v_tenure,
    'home.major_repairs_responsibility',v_repairs,
    'grounds.responsibility',v_grounds,
    'grounds.mowing_method',v_mowing,
    'transport.vehicle_count',v_vehicle_count,
    'context.low_density_owner_household',false,
    'context.dense_urban_renter',false
  )||v_candidates;

  return jsonb_build_object(
    'ok',true,'contractVersion','reality_discovery_context_self_api_v1',
    'principalId',v_principal.id,'householdId',v_household.id,
    'signals',v_signals,'answers',v_answers,'candidateEvidence',v_candidates,
    'canonicalResidence',case when v_residence.id is null then null else jsonb_build_object(
      'id',v_residence.id,'address',v_residence.address,'tenureKind',v_residence.tenure_kind,
      'majorRepairsResponsibility',v_residence.major_repairs_responsibility
    ) end,
    'truthBoundary',jsonb_build_object(
      'signalsAreDiscoveryContext',true,'purchaseContactIsCandidateEvidence',true,
      'canonicalResidenceOutranksDiscoveryAnswer',true,'inferenceIsNotDomainTruth',true,
      'candidateEvidenceRequiresConfirmationOrPromotion',true,'sensitiveTraitsNotInferred',true
    )
  );
end;
$function$;

-- Replace answer writer to promote only the home facts for which a canonical authority now exists.
create or replace function atlas.answer_reality_discovery_question_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_question atlas.reality_discovery_questions%rowtype;
  v_question_key text;
  v_source_action_id text;
  v_answer jsonb;
  v_answer_scalar text;
  v_existing atlas.reality_discovery_answer_events%rowtype;
  v_event atlas.reality_discovery_answer_events%rowtype;
  v_signal_key text;
  v_context jsonb;
  v_address jsonb;
  v_promotion jsonb;
  v_promoted boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Discovery answer input must be an object.' using errcode='22023'; end if;

  v_question_key:=nullif(trim(p_input->>'questionKey'),'');
  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_answer:=p_input->'answer';
  if v_question_key is null or v_source_action_id is null or v_answer is null then
    raise exception 'questionKey, sourceActionId, and answer are required.' using errcode='22023';
  end if;

  select * into v_question from atlas.reality_discovery_questions where question_key=v_question_key and active;
  if v_question.question_key is null then raise exception 'Active discovery question not found.' using errcode='22023'; end if;

  if v_question.answer_kind in ('single_choice','yes_no') then
    if jsonb_typeof(v_answer)<>'string' then raise exception 'This discovery answer must be a choice key.' using errcode='22023'; end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
    if not exists(select 1 from jsonb_array_elements(v_question.options) o where o->>'key'=v_answer_scalar) then
      raise exception 'Unsupported answer option.' using errcode='22023';
    end if;
  elsif v_question.answer_kind='short_text' then
    if jsonb_typeof(v_answer)<>'string' or length(trim(both '"' from v_answer::text))=0 then
      raise exception 'A non-empty answer is required.' using errcode='22023';
    end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
  end if;

  select * into v_existing from atlas.reality_discovery_answer_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;
  if v_existing.id is not null then
    if v_existing.question_key is distinct from v_question_key or v_existing.answer_value is distinct from v_answer then
      raise exception 'sourceActionId already belongs to a different discovery answer.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotentReplay',true,'eventId',v_existing.id,'next',atlas.reality_discovery_next_question_self_api_v1());
  end if;

  insert into atlas.reality_discovery_answer_events(principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata)
  values(v_principal.id,v_user_id,v_question_key,v_source_action_id,v_answer,
    jsonb_build_object('source','reality_discovery_v1','reason',v_question.reason_text))
  returning * into v_event;

  v_signal_key:=v_question.resolved_signal_key;
  if v_signal_key is not null then
    insert into atlas.reality_discovery_evidence_candidates(
      principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation,metadata
    ) values(
      v_principal.id,v_user_id,v_signal_key,v_answer,'human_confirmed','discovery_answer',v_event.id::text,1,
      'Human answer captured through Reality Discovery.',jsonb_build_object('questionKey',v_question_key)
    );
  end if;

  if v_question_key='home.confirm_purchase_address' then
    v_context:=atlas.reality_discovery_context_self_api_v1();
    v_address:=v_context#>'{candidateEvidence,purchase.billing_address}';
    if v_answer_scalar='yes' and v_address is not null and v_address<>'null'::jsonb then
      v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
        'stableKey','primary-home','address',v_address,
        'sourceKind','reality_discovery','sourceRef',v_event.id::text
      ));
      v_promoted:=true;
      update atlas.reality_discovery_evidence_candidates
      set epistemic_state='promoted',updated_at=now(),metadata=metadata||jsonb_build_object('promotion','household_residence_arrangement')
      where principal_id=v_principal.id and source_ref=v_event.id::text and signal_key=v_signal_key;
    else
      insert into atlas.reality_discovery_evidence_candidates(
        principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation
      ) values(
        v_principal.id,v_user_id,'purchase.billing_address',coalesce(v_address,'{}'::jsonb),'human_rejected',
        'discovery_answer',v_event.id::text,1,'The human rejected the purchase address as their home.'
      );
    end if;
  elsif v_question_key='home.tenure' then
    v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
      'stableKey','primary-home','tenureKind',v_answer_scalar,
      'sourceKind','reality_discovery','sourceRef',v_event.id::text
    ));
    v_promoted:=true;
  elsif v_question_key='home.major_repairs' then
    v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
      'stableKey','primary-home','majorRepairsResponsibility',v_answer_scalar,
      'sourceKind','reality_discovery','sourceRef',v_event.id::text
    ));
    v_promoted:=true;
  end if;

  if v_promoted then
    update atlas.reality_discovery_evidence_candidates
    set epistemic_state='promoted',updated_at=now(),metadata=metadata||jsonb_build_object('promotion','household_residence_arrangement')
    where principal_id=v_principal.id and source_ref=v_event.id::text and signal_key=v_signal_key;
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','answer_reality_discovery_question_self_api_v1',
    'idempotentReplay',false,'eventId',v_event.id,
    'promoted',v_promoted,'promotion',v_promotion,
    'next',atlas.reality_discovery_next_question_self_api_v1(),
    'truthBoundary',jsonb_build_object(
      'answerIsEvidence',true,'answerDoesNotBypassOwningDomain',true,
      'residencePromotionUsesResidenceAuthority',true,'inferenceMayRerankButNotEstablishTruth',true
    )
  );
end;
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
('atlas.upsert_personal_residence_arrangement_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Establish/update the authenticated Principal household residence arrangement from explicit human-confirmed residence, tenure, or repair-responsibility testimony.'),now()),
('atlas.personal_residence_arrangement_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Read the active household residence arrangement without treating purchase address evidence as residence truth.'),now())
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();
