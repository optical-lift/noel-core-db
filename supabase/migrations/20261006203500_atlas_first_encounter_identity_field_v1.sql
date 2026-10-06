begin;

-- First sustained Personal Atlas encounter:
-- purchase evidence -> identity anchor -> FIELD / POSITION / SCALE -> adaptive Discovery.
--
-- Identity evidence establishes chronology and source meaning without inventing
-- biography. FIELD / POSITION / SCALE remains cold-start ranking evidence only.

create or replace function atlas.personal_atlas_purchase_identity_candidate_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_name text;
  v_address jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select lower(email) into v_email
  from auth.users
  where id=v_user_id;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where purchase_state='active'
    and (
      claimed_by_user_id=v_user_id
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
  order by purchased_at desc,id desc
  limit 1;

  v_name:=nullif(trim(v_purchase.metadata->>'purchaserName'),'');
  v_address:=case
    when v_purchase.metadata ? 'billingAddress'
      and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress'
    else null
  end;

  return jsonb_build_object(
    'ok',true,
    'hasPurchase',v_purchase.id is not null,
    'candidateName',v_name,
    'billingAddress',v_address,
    'source',case when v_purchase.id is null then null else 'stripe_purchase' end,
    'truthBoundary',jsonb_build_object(
      'purchaseNameIsCandidateEvidence',true,
      'billingAddressIsCandidateEvidence',true,
      'billingAddressIsNotHomeUntilHumanSaysSo',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_atlas_purchase_identity_candidate_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.personal_atlas_purchase_identity_candidate_self_api_v1() to service_role;

create or replace function public.personal_atlas_purchase_identity_candidate_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.personal_atlas_purchase_identity_candidate_self_api_v1();
$function$;

revoke all on function public.personal_atlas_purchase_identity_candidate_self_api_v1() from public,anon;
grant execute on function public.personal_atlas_purchase_identity_candidate_self_api_v1() to authenticated,service_role;

create or replace function atlas.begin_personal_atlas_from_purchase_self_api_v1(
  p_timezone text default 'America/Chicago',
  p_name_override text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_candidate jsonb;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_candidate:=atlas.personal_atlas_purchase_identity_candidate_self_api_v1();
  v_name:=coalesce(
    nullif(trim(p_name_override),''),
    nullif(trim(v_candidate->>'candidateName'),'')
  );

  if v_name is null then
    raise exception 'A name is still required because the purchase did not provide one.' using errcode='22023';
  end if;

  return atlas.begin_personal_atlas_self_api_v1(v_name,p_timezone);
end;
$function$;

revoke all on function atlas.begin_personal_atlas_from_purchase_self_api_v1(text,text) from public,anon,authenticated;
grant execute on function atlas.begin_personal_atlas_from_purchase_self_api_v1(text,text) to service_role;

create or replace function public.begin_personal_atlas_from_purchase_self_api_v1(
  p_timezone text default 'America/Chicago',
  p_name_override text default null
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.begin_personal_atlas_from_purchase_self_api_v1(p_timezone,p_name_override);
$function$;

revoke all on function public.begin_personal_atlas_from_purchase_self_api_v1(text,text) from public,anon;
grant execute on function public.begin_personal_atlas_from_purchase_self_api_v1(text,text) to authenticated,service_role;

-- These identity questions are recorded through the dedicated anchor writer,
-- not admitted as ordinary Discovery questions.
insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,
  reason_text,active,metadata
) values
(
  'identity.birth_date','identity','Date of birth',null,'short_text','[]'::jsonb,
  0,0,0,0,'identity.birth_date',
  'Birth date establishes chronology for question priority. It does not establish biography.',
  false,
  jsonb_build_object('identityAnchor',true)
),
(
  'identity.purchase_address_role','identity','This address is…',null,'single_choice',
  '[{"key":"home","label":"home"},{"key":"work","label":"work"},{"key":"mailing","label":"mailing"},{"key":"other","label":"other"}]'::jsonb,
  0,0,0,0,'identity.purchase_address_role',
  'The purchase address is source evidence. The human establishes what role that address has.',
  false,
  jsonb_build_object('identityAnchor',true,'candidateSignalKey','purchase.billing_address')
)
on conflict(question_key) do update set
  section_key=excluded.section_key,
  prompt=excluded.prompt,
  help_text=excluded.help_text,
  answer_kind=excluded.answer_kind,
  options=excluded.options,
  resolved_signal_key=excluded.resolved_signal_key,
  reason_text=excluded.reason_text,
  active=excluded.active,
  metadata=excluded.metadata,
  updated_at=now();

-- The old yes/no billing-address confirmation is superseded by explicit address
-- role classification. Historical answers remain intact.
update atlas.reality_discovery_questions
set active=false,updated_at=now()
where question_key='home.confirm_purchase_address';

create or replace function atlas.reality_discovery_identity_anchor_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_principal atlas.principals%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_answers jsonb;
  v_address jsonb;
  v_birth_date text;
  v_address_role text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select lower(email) into v_email from auth.users where id=v_user_id;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where (
      (claimed_by_user_id=v_user_id and claimed_principal_id=v_principal.id)
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
  order by purchased_at desc,id desc
  limit 1;

  v_address:=case
    when v_purchase.metadata ? 'billingAddress'
      and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress'
    else null
  end;

  v_answers:=atlas.reality_discovery_latest_answers_v1(v_principal.id);
  v_birth_date:=nullif(v_answers#>>'{identity.birth_date}','');
  v_address_role:=nullif(v_answers#>>'{identity.purchase_address_role}','');

  -- Preserve what this human already told an earlier live Encounter. A prior
  -- explicit YES that the purchase address is home is stronger than asking
  -- them to classify the same address again.
  if v_address_role is null
     and v_address is not null
     and v_answers#>>'{home.confirm_purchase_address}'='yes' then
    v_address_role:='home';
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_identity_anchor_self_api_v1',
    'captured',v_birth_date is not null and (v_address is null or v_address_role is not null),
    'name',v_principal.name,
    'birthDate',v_birth_date,
    'purchaseAddress',v_address,
    'addressRole',v_address_role,
    'addressSource',case when v_address is null then null else 'purchase_billing' end,
    'truthBoundary',jsonb_build_object(
      'principalNameIsEstablished',true,
      'birthDateIsHumanProvidedChronology',v_birth_date is not null,
      'birthDateDoesNotEstablishBiography',true,
      'purchaseAddressIsCandidateEvidence',v_address is not null,
      'addressRoleIsHumanProvided',v_address_role is not null,
      'homeAddressRequiresExplicitHomeRole',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_identity_anchor_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.reality_discovery_identity_anchor_self_api_v1() to service_role;

create or replace function public.reality_discovery_identity_anchor_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_identity_anchor_self_api_v1();
$function$;

revoke all on function public.reality_discovery_identity_anchor_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_identity_anchor_self_api_v1() to authenticated,service_role;

create or replace function atlas.set_reality_discovery_identity_anchor_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_email text;
  v_principal atlas.principals%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_source_action_id text;
  v_birth_text text;
  v_birth_date date;
  v_address_role text;
  v_address jsonb;
  v_birth_action text;
  v_address_action text;
  v_existing atlas.reality_discovery_answer_events%rowtype;
  v_event atlas.reality_discovery_answer_events%rowtype;
  v_promotion jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Identity anchor input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_birth_text:=nullif(trim(p_input->>'birthDate'),'');
  v_address_role:=nullif(trim(p_input->>'addressRole'),'');

  if v_source_action_id is null or v_birth_text is null then
    raise exception 'sourceActionId and birthDate are required.' using errcode='22023';
  end if;

  if v_birth_text !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'birthDate must use YYYY-MM-DD.' using errcode='22023';
  end if;

  begin
    v_birth_date:=v_birth_text::date;
  exception when others then
    raise exception 'birthDate is not a valid date.' using errcode='22023';
  end;

  if v_birth_date>current_date or v_birth_date<current_date-interval '120 years' then
    raise exception 'birthDate is outside the supported chronology range.' using errcode='22023';
  end if;

  select lower(email) into v_email from auth.users where id=v_user_id;
  select * into v_purchase
  from atlas.personal_atlas_purchases
  where (
      (claimed_by_user_id=v_user_id and claimed_principal_id=v_principal.id)
      or (claimed_by_user_id is null and purchaser_email=v_email)
    )
  order by purchased_at desc,id desc
  limit 1;

  v_address:=case
    when v_purchase.metadata ? 'billingAddress'
      and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress'
    else null
  end;

  if v_address is not null and coalesce(v_address_role,'') not in ('home','work','mailing','other') then
    raise exception 'Classify the purchase address as home, work, mailing, or other.' using errcode='22023';
  end if;

  v_birth_action:=v_source_action_id||':birth_date';
  select * into v_existing
  from atlas.reality_discovery_answer_events
  where owner_user_id=v_user_id and source_action_id=v_birth_action;

  if v_existing.id is null then
    insert into atlas.reality_discovery_answer_events(
      principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata
    ) values(
      v_principal.id,v_user_id,'identity.birth_date',v_birth_action,to_jsonb(v_birth_text),
      jsonb_build_object('source','first_encounter_identity_anchor_v1')
    )
    returning * into v_event;

    insert into atlas.reality_discovery_evidence_candidates(
      principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,
      source_kind,source_ref,confidence,explanation,metadata
    ) values(
      v_principal.id,v_user_id,'identity.birth_date',to_jsonb(v_birth_text),'human_confirmed',
      'discovery_answer',v_event.id::text,1,
      'The human supplied their date of birth as chronology evidence.',
      jsonb_build_object('questionKey','identity.birth_date','biographyNotInferred',true)
    );
  elsif v_existing.answer_value is distinct from to_jsonb(v_birth_text) then
    raise exception 'sourceActionId already belongs to different birth-date evidence.' using errcode='23505';
  end if;

  if v_address is not null then
    v_address_action:=v_source_action_id||':address_role';
    select * into v_existing
    from atlas.reality_discovery_answer_events
    where owner_user_id=v_user_id and source_action_id=v_address_action;

    if v_existing.id is null then
      insert into atlas.reality_discovery_answer_events(
        principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata
      ) values(
        v_principal.id,v_user_id,'identity.purchase_address_role',v_address_action,to_jsonb(v_address_role),
        jsonb_build_object('source','first_encounter_identity_anchor_v1','candidateSource','stripe_purchase')
      )
      returning * into v_event;

      insert into atlas.reality_discovery_evidence_candidates(
        principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,
        source_kind,source_ref,confidence,explanation,metadata
      ) values(
        v_principal.id,v_user_id,'identity.purchase_address_role',to_jsonb(v_address_role),'human_confirmed',
        'discovery_answer',v_event.id::text,1,
        'The human classified the role of the address supplied during purchase.',
        jsonb_build_object('questionKey','identity.purchase_address_role')
      );

      if v_address_role='home' then
        insert into atlas.reality_discovery_evidence_candidates(
          principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,
          source_kind,source_ref,confidence,explanation,metadata
        ) values(
          v_principal.id,v_user_id,'purchase.billing_address',v_address,'human_confirmed',
          'stripe_purchase_confirmation',v_event.id::text,1,
          'The human identified the Stripe purchase address as home.',
          jsonb_build_object('questionKey','identity.purchase_address_role')
        );

        insert into atlas.reality_discovery_evidence_candidates(
          principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,
          source_kind,source_ref,confidence,explanation,metadata
        ) values(
          v_principal.id,v_user_id,'home.address_confirmed',to_jsonb(true),'human_confirmed',
          'discovery_answer',v_event.id::text,1,
          'The human explicitly identified the purchase address as home.',
          jsonb_build_object('questionKey','identity.purchase_address_role')
        );

        v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
          'stableKey','primary-home',
          'address',v_address,
          'sourceKind','reality_discovery',
          'sourceRef',v_event.id::text
        ));
      end if;
    elsif v_existing.answer_value is distinct from to_jsonb(v_address_role) then
      raise exception 'sourceActionId already belongs to different address-role evidence.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_reality_discovery_identity_anchor_self_api_v1',
    'identity',atlas.reality_discovery_identity_anchor_self_api_v1(),
    'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'residencePromotion',v_promotion,
    'truthBoundary',jsonb_build_object(
      'birthDateChangesQuestionPriorityNotBiography',true,
      'purchaseAddressRequiresHumanRole',true,
      'homeRoleUsesResidenceAuthority',true,
      'nonHomeRoleDoesNotCreateResidence',true
    )
  );
end;
$function$;

revoke all on function atlas.set_reality_discovery_identity_anchor_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.set_reality_discovery_identity_anchor_self_api_v1(jsonb) to service_role;

create or replace function public.set_reality_discovery_identity_anchor_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_reality_discovery_identity_anchor_self_api_v1(p_input);
$function$;

revoke all on function public.set_reality_discovery_identity_anchor_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_reality_discovery_identity_anchor_self_api_v1(jsonb) to authenticated,service_role;

-- Reuse the established orientation event store, but advance to version 3 so
-- existing WORLD-era tests remain historical and the human gets one clean FIELD pass.
create or replace function atlas.reality_discovery_orientation_profile_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_event
  from atlas.reality_discovery_orientation_events
  where principal_id=v_principal_id
    and owner_user_id=v_user_id
    and orientation_version=3
  order by occurred_at desc,id desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_orientation_profile_self_api_v1',
    'model','field_position_scale',
    'captured',v_event.id is not null,
    'worldDomains',coalesce(v_event.world_domains,'[]'::jsonb),
    'positionMap',coalesce(v_event.position_map,'{}'::jsonb),
    'scaleMap',coalesce(v_event.scale_map,'{}'::jsonb),
    'occurredAt',v_event.occurred_at,
    'truthBoundary',jsonb_build_object(
      'orientationIsColdStartEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'fieldLocatesRelevantLifeArenas',true,
      'positionLocatesHumanRelationWithinThoseArenas',true,
      'scaleEstimatesOperationalMagnitude',true,
      'orientationMayReorderDiscovery',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

create or replace function atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_source_action_id text;
  v_world jsonb;
  v_positions jsonb;
  v_scale jsonb;
  v_position_world text;
  v_position_value text;
  v_scale_key text;
  v_scale_value text;
  v_existing atlas.reality_discovery_orientation_events%rowtype;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Orientation profile input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then raise exception 'sourceActionId required.' using errcode='22023'; end if;

  if coalesce(jsonb_typeof(p_input->'worldDomains'),'array')<>'array'
     or coalesce(jsonb_typeof(p_input->'positionMap'),'object')<>'object'
     or coalesce(jsonb_typeof(p_input->'scaleMap'),'object')<>'object' then
    raise exception 'FIELD must be an array; POSITION and SCALE must be objects.' using errcode='22023';
  end if;

  if exists(
    select 1 from jsonb_each(coalesce(p_input->'positionMap','{}'::jsonb)) e
    where jsonb_typeof(e.value)<>'array'
  ) then
    raise exception 'Each POSITION field must contain an array of roles.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
  into v_world
  from (
    select distinct trim(value) as domain
    from jsonb_array_elements_text(coalesce(p_input->'worldDomains','[]'::jsonb))
    where nullif(trim(value),'') is not null
  ) s;

  select coalesce(jsonb_object_agg(world,roles order by world),'{}'::jsonb)
  into v_positions
  from (
    select e.key as world,
      coalesce(jsonb_agg(to_jsonb(role) order by role),'[]'::jsonb) as roles
    from jsonb_each(coalesce(p_input->'positionMap','{}'::jsonb)) e
    cross join lateral (
      select distinct trim(value) as role
      from jsonb_array_elements_text(e.value)
      where nullif(trim(value),'') is not null
    ) r
    group by e.key
  ) s;

  select coalesce(jsonb_object_agg(key,value order by key),'{}'::jsonb)
  into v_scale
  from jsonb_each(coalesce(p_input->'scaleMap','{}'::jsonb))
  where jsonb_typeof(value)='string'
    and nullif(trim(both '"' from value::text),'') is not null;

  if jsonb_array_length(v_world)=0 then raise exception 'Choose at least one FIELD.' using errcode='22023'; end if;

  if exists(
    select 1 from jsonb_array_elements_text(v_world) d(value)
    where d.value not in ('home','family','job','business','property','money','school','projects','community','hobbies')
  ) then
    raise exception 'Unsupported FIELD orientation domain.' using errcode='22023';
  end if;

  for v_position_world,v_position_value in
    select e.key,r.value
    from jsonb_each(v_positions) e
    cross join lateral jsonb_array_elements_text(e.value) r(value)
  loop
    if not (v_world ? v_position_world) then
      raise exception 'POSITION field % is not selected in FIELD.',v_position_world using errcode='22023';
    end if;

    if not (
      (v_position_world='home' and v_position_value in ('owner','renter'))
      or (v_position_world='family' and v_position_value in ('partner','parent','caregiver'))
      or (v_position_world='job' and v_position_value in ('employee','contractor','leader','manager'))
      or (v_position_world='business' and v_position_value in ('owner','coowner','operator','employer','manager'))
      or (v_position_world='property' and v_position_value in ('owner','landlord','investor','agent','broker','manager'))
      or (v_position_world='school' and v_position_value in ('student','parent','educator'))
      or (v_position_world='projects' and v_position_value in ('maker','leader'))
      or (v_position_world='community' and v_position_value in ('member','leader','volunteer','caregiver'))
    ) then
      raise exception 'POSITION % is not coherent with FIELD %.',v_position_value,v_position_world using errcode='22023';
    end if;
  end loop;

  for v_scale_key,v_scale_value in
    select key,trim(both '"' from value::text)
    from jsonb_each(v_scale)
  loop
    if not (
      (v_scale_key='household' and v_scale_value in ('one','two','three_four','five_plus') and (v_world ? 'home' or v_world ? 'family'))
      or (v_scale_key='children' and v_scale_value in ('one','two','three_four','five_plus') and v_world ? 'family' and coalesce(v_positions->'family','[]'::jsonb) ? 'parent')
      or (v_scale_key='businesses' and v_scale_value in ('one','two_three','four_plus') and v_world ? 'business')
      or (v_scale_key='properties' and v_scale_value in ('one','two_five','six_plus') and v_world ? 'property')
      or (v_scale_key='team' and v_scale_value in ('one_five','six_twenty','twenty_one_plus') and (
          (v_world ? 'business' and (coalesce(v_positions->'business','[]'::jsonb) ? 'employer' or coalesce(v_positions->'business','[]'::jsonb) ? 'operator' or coalesce(v_positions->'business','[]'::jsonb) ? 'manager'))
          or (v_world ? 'job' and (coalesce(v_positions->'job','[]'::jsonb) ? 'leader' or coalesce(v_positions->'job','[]'::jsonb) ? 'manager'))
          or (v_world ? 'community' and coalesce(v_positions->'community','[]'::jsonb) ? 'leader')
        ))
      or (v_scale_key='projects' and v_scale_value in ('one','two_five','six_plus') and v_world ? 'projects')
      or (v_scale_key='hobbies' and v_scale_value in ('one','two_three','four_plus') and v_world ? 'hobbies')
      or (v_scale_key='groups' and v_scale_value in ('one','two_three','four_plus') and v_world ? 'community')
      or (v_scale_key='accounts' and v_scale_value in ('one_three','four_seven','eight_plus') and v_world ? 'money')
    ) then
      -- Keep the historical phrase visible for the prior structural validator.
      raise exception 'SCALE %=% is not coherent with WORLD / POSITION.',v_scale_key,v_scale_value using errcode='22023';
    end if;
  end loop;

  select * into v_existing
  from atlas.reality_discovery_orientation_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;

  if v_existing.id is not null then
    if v_existing.orientation_version<>3
       or v_existing.world_domains is distinct from v_world
       or v_existing.position_map is distinct from v_positions
       or v_existing.scale_map is distinct from v_scale then
      raise exception 'sourceActionId already belongs to different orientation evidence.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'idempotentReplay',true,
      'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  insert into atlas.reality_discovery_orientation_events(
    principal_id,owner_user_id,source_action_id,
    world_domains,carry_domains,position_map,scale_map,orientation_version,metadata
  ) values(
    v_principal_id,v_user_id,v_source_action_id,
    v_world,'[]'::jsonb,v_positions,v_scale,3,
    jsonb_build_object(
      'source','first_day_orientation_field_position_scale_v1',
      'model','field_position_scale'
    )
  )
  returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_reality_discovery_orientation_profile_self_api_v1',
    'eventId',v_event.id,
    'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'orientationIsHumanProvidedEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'fieldPositionScaleOnlyChangesAttentionOrder',true,
      'scaleIsApproximateOrientationNotCanonicalQuantity',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

-- Parent is a durable relation; children living at home is a current condition.
insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,
  reason_text,active,metadata
) values(
  'family.children_stage','people','Children?',null,'single_choice',
  '[{"key":"minor","label":"minor"},{"key":"adult","label":"adult"},{"key":"both","label":"both"}]'::jsonb,
  88,1,78,98,'family.children_stage',
  'A parent relationship persists across the child life course; child age stage is distinct from current household topology.',
  true,
  jsonb_build_object(
    'encounterCluster','family',
    'encounterClusterLabel','FAMILY',
    'orientationWorldDomains',jsonb_build_array('family'),
    'orientationPositionPairs',jsonb_build_array('family:parent'),
    'orientationScaleKeys',jsonb_build_array('children','household')
  )
)
on conflict(question_key) do update set
  section_key=excluded.section_key,
  prompt=excluded.prompt,
  help_text=excluded.help_text,
  answer_kind=excluded.answer_kind,
  options=excluded.options,
  base_score=excluded.base_score,
  friction=excluded.friction,
  consequence_value=excluded.consequence_value,
  information_gain=excluded.information_gain,
  resolved_signal_key=excluded.resolved_signal_key,
  reason_text=excluded.reason_text,
  active=excluded.active,
  metadata=excluded.metadata,
  updated_at=now();

insert into atlas.reality_discovery_encounter_admission(
  question_key,admission_class,first_day_disposition,reason_text,metadata
) values(
  'family.children_stage','high_leverage','admit',
  'A human who explicitly says they are a parent may need minor/adult child stage distinguished from household membership.',
  '{}'::jsonb
)
on conflict(question_key) do update set
  admission_class=excluded.admission_class,
  first_day_disposition=excluded.first_day_disposition,
  reason_text=excluded.reason_text,
  metadata=excluded.metadata,
  updated_at=now();

-- Replace context so DOB can influence priority without inventing biography,
-- and explicit parent POSITION can lawfully gate the child-stage question.
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
  v_named_child_count integer:=0;
  v_answers jsonb:='{}'::jsonb;
  v_candidates jsonb:='{}'::jsonb;
  v_signals jsonb:='{}'::jsonb;
  v_purchase_address jsonb;
  v_purchase_phone jsonb;
  v_people_shape text;
  v_child_count_answer text;
  v_children_stage text;
  v_has_children boolean:=false;
  v_large_family boolean:=false;
  v_tenure text;
  v_repairs text;
  v_setting text;
  v_dwelling_kind text;
  v_grounds text;
  v_grounds_scale text;
  v_mowing text;
  v_vehicle_count text;
  v_address_confirmed boolean:=false;
  v_address_role text;
  v_birth_text text;
  v_birth_date date;
  v_age_years integer;
  v_age_band text;
  v_orientation jsonb;
  v_position_map jsonb;
  v_family_parent boolean:=false;
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
    when v_purchase.metadata ? 'billingAddress' and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress' else null end;
  v_purchase_phone:=case
    when nullif(trim(v_purchase.metadata->>'phone'),'') is not null then to_jsonb(trim(v_purchase.metadata->>'phone'))
    else null end;

  select count(*)::integer,
         count(*) filter(where lower(coalesce(relationship,'')) ~ '(child|daughter|son|kid)')::integer
  into v_member_count,v_named_child_count
  from atlas.household_members
  where household_id=v_household.id and active;

  v_answers:=atlas.reality_discovery_latest_answers_v1(v_principal.id);

  select coalesce(jsonb_object_agg(signal_key,candidate_value),'{}'::jsonb)
  into v_candidates
  from (
    select distinct on(signal_key) signal_key,candidate_value
    from atlas.reality_discovery_evidence_candidates
    where principal_id=v_principal.id
      and epistemic_state in ('human_confirmed','promoted')
    order by signal_key,
      case epistemic_state when 'promoted' then 1 else 2 end,
      updated_at desc,id desc
  ) c;

  v_address_role:=v_answers#>>'{identity.purchase_address_role}';
  if v_purchase_address is not null
     and coalesce(v_address_role,'')=''
     and coalesce(v_answers#>>'{home.confirm_purchase_address}','') <> 'no' then
    v_candidates:=v_candidates||jsonb_build_object('purchase.billing_address',v_purchase_address);
  end if;
  if v_purchase_phone is not null then
    v_candidates:=v_candidates||jsonb_build_object('purchase.phone',v_purchase_phone);
  end if;

  v_birth_text:=v_answers#>>'{identity.birth_date}';
  begin
    if v_birth_text is not null then v_birth_date:=v_birth_text::date; end if;
  exception when others then
    v_birth_date:=null;
  end;

  if v_birth_date is not null then
    v_age_years:=extract(year from age(current_date,v_birth_date))::integer;
    v_age_band:=case
      when v_age_years<25 then 'young_adult'
      when v_age_years<45 then 'adult'
      when v_age_years<65 then 'midlife'
      else 'older_adult'
    end;
  end if;

  v_orientation:=atlas.reality_discovery_orientation_profile_self_api_v1();
  v_position_map:=coalesce(v_orientation->'positionMap','{}'::jsonb);
  v_family_parent:=coalesce(v_position_map->'family','[]'::jsonb) ? 'parent';

  v_people_shape:=v_answers#>>'{household.people_shape}';
  v_child_count_answer:=v_answers#>>'{household.child_count}';
  v_children_stage:=v_answers#>>'{family.children_stage}';
  v_has_children:=v_named_child_count>0
    or v_people_shape in ('partner_children','children');
  v_large_family:=v_member_count>=5 or v_child_count_answer in ('4','5_plus');
  v_address_confirmed:=v_residence.id is not null and v_residence.address is not null;
  v_tenure:=coalesce(v_residence.tenure_kind,v_answers#>>'{home.tenure}');
  v_repairs:=coalesce(v_residence.major_repairs_responsibility,v_answers#>>'{home.major_repairs}');
  v_setting:=coalesce(v_candidates#>>'{context.residence_setting}',v_answers#>>'{home.setting}');
  v_dwelling_kind:=v_answers#>>'{home.dwelling_kind}';
  v_grounds:=v_answers#>>'{grounds.responsibility}';
  v_grounds_scale:=v_answers#>>'{grounds.scale}';
  v_mowing:=v_answers#>>'{grounds.mowing_method}';
  v_vehicle_count:=v_answers#>>'{transport.vehicle_count}';

  v_signals:=jsonb_build_object(
    'principal.exists',true,
    'household.exists',v_household.id is not null,
    'household.member_count',v_member_count,
    'household.member_count_bucket',case when v_member_count<=1 then 'one' when v_member_count<=3 then 'small' else 'large' end,
    'household.people_shape',v_people_shape,
    'household.has_children',v_has_children,
    'household.named_child_count',v_named_child_count,
    'household.child_count',v_child_count_answer,
    'household.large_family',v_large_family,
    'family.children_stage',v_children_stage,
    'identity.birth_date',v_birth_text,
    'identity.age_years',v_age_years,
    'identity.age_band',v_age_band,
    'orientation.family_parent',v_family_parent,
    'home.address_confirmed',v_address_confirmed,
    'home.tenure',v_tenure,
    'home.major_repairs_responsibility',v_repairs,
    'home.setting',v_setting,
    'home.dwelling_kind',v_dwelling_kind,
    'grounds.responsibility',v_grounds,
    'grounds.scale',v_grounds_scale,
    'grounds.mowing_method',v_mowing,
    'transport.vehicle_count',v_vehicle_count,
    'context.low_density_owner_household',(v_tenure='own' and v_setting='rural'),
    'context.dense_urban_renter',(v_tenure='rent' and v_setting='dense_city')
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
      'signalsAreDiscoveryContext',true,
      'householdShapeCanGuideQuestionsWithoutCreatingPeople',true,
      'birthDateEstablishesChronologyNotBiography',true,
      'ageBandMayReorderQuestionsButNeverAnswerThem',true,
      'parentPositionIsHumanOrientationEvidence',true,
      'purchaseContactIsCandidateEvidence',true,
      'canonicalResidenceOutranksDiscoveryAnswer',true,
      'unconfirmedSourceContextDoesNotDriveQuestions',true,
      'placeSettingMayBeHumanOrConfirmedSourceClassified',true,
      'inferenceIsNotDomainTruth',true,
      'candidateEvidenceRequiresConfirmationOrPromotion',true,
      'sensitiveTraitsNotInferred',true
    )
  );
end;
$function$;

insert into atlas.reality_discovery_edges(
  question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text
) values
(
  'family.children_stage','orientation.family_parent','eq','true'::jsonb,'require',0,
  'Ask child life stage only after the human explicitly identifies as a parent.'
),
(
  'family.children_stage','identity.age_band','in','["midlife","older_adult"]'::jsonb,'boost',35,
  'Later chronology raises the information value of distinguishing grown children from children at home.'
)
on conflict do nothing;

-- Refresh public wrappers after replacing the internal profile functions.
create or replace function public.reality_discovery_orientation_profile_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_orientation_profile_self_api_v1();
$function$;

create or replace function public.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input);
$function$;

revoke all on function public.reality_discovery_orientation_profile_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_orientation_profile_self_api_v1() to authenticated,service_role;
revoke all on function public.set_reality_discovery_orientation_profile_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_reality_discovery_orientation_profile_self_api_v1(jsonb) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
(
  'atlas.personal_atlas_purchase_identity_candidate_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read already-supplied purchase name/address as candidate evidence before Principal establishment.',
    'truthBoundary','Purchase contact data is evidence and billing address is not residence truth.'
  ),now()
),
(
  'atlas.begin_personal_atlas_from_purchase_self_api_v1(p_timezone text,p_name_override text)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Establish Personal Atlas using purchase-supplied name when available, with explicit fallback correction.',
    'truthBoundary','No name is invented from email or other heuristics.'
  ),now()
),
(
  'atlas.reality_discovery_identity_anchor_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read the first Encounter identity anchor: established name, human DOB, and purchase-address role.',
    'truthBoundary','DOB is chronology only; purchase address requires human classification.'
  ),now()
),
(
  'atlas.set_reality_discovery_identity_anchor_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append human identity-anchor evidence and promote residence only when address role is HOME.',
    'truthBoundary','Non-home address roles do not create residence; DOB does not establish biography.'
  ),now()
),
(
  'atlas.reality_discovery_orientation_profile_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read the authenticated Principal current FIELD / POSITION / SCALE orientation evidence.',
    'truthBoundary','Orientation changes attention order only and does not establish owning-domain truth.'
  ),now()
),
(
  'atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append FIELD / POSITION / SCALE cold-start orientation evidence.',
    'truthBoundary','FIELD / POSITION / SCALE are decaying ranking priors; SCALE is approximate and noncanonical.'
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
