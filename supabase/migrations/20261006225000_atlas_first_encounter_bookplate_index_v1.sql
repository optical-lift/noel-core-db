begin;

-- Personal Atlas first encounter v2:
-- Bookplate -> intentional Index selection -> adaptive Discovery inside the real notebook.
--
-- Purchase/auth contact data remains source evidence. Human Bookplate values are
-- editable presentation truth for this Principal and never rewrite the source record.
-- Index selection organizes the notebook and constrains first-day Discovery without
-- establishing ownership, family shape, employment, wealth, or any other domain fact.

create table if not exists atlas.personal_atlas_bookplate_events (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id),
  owner_user_id uuid not null,
  source_action_id text not null,
  preferred_name text not null,
  preferred_email text,
  preferred_phone text,
  contact_address jsonb,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id)
);

revoke all on table atlas.personal_atlas_bookplate_events from public,anon,authenticated;

create index if not exists personal_atlas_bookplate_events_principal_occurred_idx
  on atlas.personal_atlas_bookplate_events(principal_id,occurred_at desc,id desc);

create or replace function atlas.personal_atlas_bookplate_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_auth_email text;
  v_auth_phone text;
  v_principal atlas.principals%rowtype;
  v_purchase atlas.personal_atlas_purchases%rowtype;
  v_event atlas.personal_atlas_bookplate_events%rowtype;
  v_purchase_name text;
  v_purchase_phone text;
  v_purchase_address jsonb;
  v_name text;
  v_email text;
  v_phone text;
  v_address jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select lower(email),nullif(trim(phone),'')
  into v_auth_email,v_auth_phone
  from auth.users
  where id=v_user_id;

  select * into v_principal
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  select * into v_purchase
  from atlas.personal_atlas_purchases
  where (
      claimed_by_user_id=v_user_id
      or (
        claimed_by_user_id is null
        and purchase_state='active'
        and purchaser_email=v_auth_email
      )
    )
  order by
    case when claimed_by_user_id=v_user_id then 0 else 1 end,
    purchased_at desc,id desc
  limit 1;

  v_purchase_name:=nullif(trim(v_purchase.metadata->>'purchaserName'),'');
  v_purchase_phone:=nullif(trim(v_purchase.metadata->>'phone'),'');
  v_purchase_address:=case
    when v_purchase.metadata ? 'billingAddress'
      and v_purchase.metadata->'billingAddress'<>'null'::jsonb
      then v_purchase.metadata->'billingAddress'
    else null
  end;

  if v_principal.id is not null then
    select * into v_event
    from atlas.personal_atlas_bookplate_events
    where principal_id=v_principal.id and owner_user_id=v_user_id
    order by occurred_at desc,id desc
    limit 1;
  end if;

  if v_event.id is not null then
    v_name:=v_event.preferred_name;
    v_email:=v_event.preferred_email;
    v_phone:=v_event.preferred_phone;
    v_address:=v_event.contact_address;
  else
    v_name:=coalesce(nullif(trim(v_principal.name),''),v_purchase_name);
    v_email:=coalesce(nullif(trim(v_purchase.purchaser_email),''),v_auth_email);
    v_phone:=coalesce(v_purchase_phone,v_auth_phone);
    v_address:=v_purchase_address;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_atlas_bookplate_self_api_v1',
    'captured',v_event.id is not null,
    'hasPrincipal',v_principal.id is not null,
    'name',v_name,
    'email',v_email,
    'phone',v_phone,
    'address',v_address,
    'sourceEvidence',jsonb_strip_nulls(jsonb_build_object(
      'purchaseName',v_purchase_name,
      'purchaseEmail',v_purchase.purchaser_email,
      'purchasePhone',v_purchase_phone,
      'purchaseBillingAddress',v_purchase_address,
      'authEmail',v_auth_email,
      'authPhone',v_auth_phone
    )),
    'truthBoundary',jsonb_build_object(
      'sourceEvidenceIsNotEditableByBookplate',true,
      'bookplateValuesAreHumanCorrectable',true,
      'preferredEmailDoesNotChangeLoginEmail',true,
      'contactAddressDoesNotEstablishResidence',true,
      'purchaseNameDoesNotBecomePreferredNameWithoutHumanAcceptance',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_atlas_bookplate_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.personal_atlas_bookplate_self_api_v1() to service_role;

create or replace function public.personal_atlas_bookplate_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.personal_atlas_bookplate_self_api_v1();
$function$;

revoke all on function public.personal_atlas_bookplate_self_api_v1() from public,anon;
grant execute on function public.personal_atlas_bookplate_self_api_v1() to authenticated,service_role;

create or replace function atlas.set_personal_atlas_bookplate_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_source_action_id text;
  v_name text;
  v_email text;
  v_phone text;
  v_timezone text;
  v_address_input jsonb;
  v_address jsonb;
  v_begin jsonb;
  v_principal atlas.principals%rowtype;
  v_existing atlas.personal_atlas_bookplate_events%rowtype;
  v_event atlas.personal_atlas_bookplate_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Bookplate input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_name:=nullif(trim(p_input->>'name'),'');
  v_email:=nullif(lower(trim(p_input->>'email')),'');
  v_phone:=nullif(trim(p_input->>'phone'),'');
  v_timezone:=coalesce(nullif(trim(p_input->>'timezone'),''),'America/Chicago');
  v_address_input:=case
    when p_input ? 'contactAddress' and p_input->'contactAddress'<>'null'::jsonb
      then p_input->'contactAddress'
    else null
  end;

  if v_source_action_id is null then
    raise exception 'sourceActionId required.' using errcode='22023';
  end if;
  if v_name is null then
    raise exception 'Name required.' using errcode='22023';
  end if;
  if v_email is not null and position('@' in v_email)<=1 then
    raise exception 'Email address is not valid.' using errcode='22023';
  end if;
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then
    raise exception 'Unknown timezone.' using errcode='22023';
  end if;
  if v_address_input is not null and jsonb_typeof(v_address_input)<>'object' then
    raise exception 'contactAddress must be an object.' using errcode='22023';
  end if;

  if v_address_input is not null then
    v_address:=jsonb_strip_nulls(jsonb_build_object(
      'line1',nullif(trim(v_address_input->>'line1'),''),
      'line2',nullif(trim(v_address_input->>'line2'),''),
      'city',nullif(trim(v_address_input->>'city'),''),
      'state',nullif(trim(v_address_input->>'state'),''),
      'postalCode',coalesce(
        nullif(trim(v_address_input->>'postalCode'),''),
        nullif(trim(v_address_input->>'postal_code'),'')
      ),
      'country',nullif(trim(v_address_input->>'country'),'')
    ));
    if v_address='{}'::jsonb then v_address:=null; end if;
  end if;

  select * into v_existing
  from atlas.personal_atlas_bookplate_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;

  if v_existing.id is not null then
    if v_existing.preferred_name is distinct from v_name
       or v_existing.preferred_email is distinct from v_email
       or v_existing.preferred_phone is distinct from v_phone
       or v_existing.contact_address is distinct from v_address then
      raise exception 'sourceActionId already belongs to different Bookplate evidence.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,
      'idempotentReplay',true,
      'bookplate',atlas.personal_atlas_bookplate_self_api_v1()
    );
  end if;

  select * into v_principal
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal.id is null then
    v_begin:=atlas.begin_personal_atlas_self_api_v1(v_name,v_timezone);
    select * into v_principal
    from atlas.principals
    where user_id=v_user_id and status='active'
    limit 1;
  end if;

  if v_principal.id is null then
    raise exception 'Atlas could not establish an active Principal.' using errcode='42501';
  end if;

  update atlas.principals
  set name=v_name,updated_at=now()
  where id=v_principal.id;

  update atlas.household_members hm
  set display_name=v_name,updated_at=now()
  from atlas.households h
  where h.id=hm.household_id
    and h.principal_id=v_principal.id
    and hm.user_id=v_user_id
    and hm.relationship='self'
    and hm.active;

  insert into atlas.personal_atlas_bookplate_events(
    principal_id,owner_user_id,source_action_id,
    preferred_name,preferred_email,preferred_phone,contact_address,metadata
  ) values(
    v_principal.id,v_user_id,v_source_action_id,
    v_name,v_email,v_phone,v_address,
    jsonb_build_object(
      'source','human_bookplate',
      'sourceEvidencePreservedSeparately',true,
      'loginEmailUnaffected',true,
      'contactAddressIsNotResidence',true
    )
  )
  returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_personal_atlas_bookplate_self_api_v1',
    'eventId',v_event.id,
    'bookplate',atlas.personal_atlas_bookplate_self_api_v1(),
    'truthBoundary',jsonb_build_object(
      'bookplateCorrectionDoesNotRewritePurchaseEvidence',true,
      'preferredEmailDoesNotChangeAuthCredential',true,
      'contactAddressDoesNotCreateResidence',true
    )
  );
end;
$function$;

revoke all on function atlas.set_personal_atlas_bookplate_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.set_personal_atlas_bookplate_self_api_v1(jsonb) to service_role;

create or replace function public.set_personal_atlas_bookplate_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_personal_atlas_bookplate_self_api_v1(p_input);
$function$;

revoke all on function public.set_personal_atlas_bookplate_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_personal_atlas_bookplate_self_api_v1(jsonb) to authenticated,service_role;

create or replace function atlas.personal_atlas_index_selection_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_current atlas.reality_discovery_orientation_events%rowtype;
  v_prior atlas.reality_discovery_orientation_events%rowtype;
  v_categories jsonb:='[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_current
  from atlas.reality_discovery_orientation_events
  where principal_id=v_principal_id
    and owner_user_id=v_user_id
    and orientation_version=4
  order by occurred_at desc,id desc
  limit 1;

  if v_current.id is null then
    select * into v_prior
    from atlas.reality_discovery_orientation_events
    where principal_id=v_principal_id
      and owner_user_id=v_user_id
      and orientation_version=3
    order by occurred_at desc,id desc
    limit 1;
  end if;

  v_categories:=case
    when v_current.id is not null then coalesce(v_current.world_domains,'[]'::jsonb)
    else coalesce(v_prior.world_domains,'[]'::jsonb)
  end;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_atlas_index_selection_self_api_v1',
    'captured',v_current.id is not null,
    'selectedCategories',v_categories,
    'suggestedFromPriorOrientation',v_current.id is null and v_prior.id is not null,
    'occurredAt',v_current.occurred_at,
    'truthBoundary',jsonb_build_object(
      'selectionOrganizesNotebook',true,
      'selectionDoesNotEstablishDomainTruth',true,
      'selectionDoesNotEstablishRoleOrScale',true,
      'selectionMayConstrainAndPrioritizeDiscovery',true,
      'selectionIsEditableByAppendingNewEvidence',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_atlas_index_selection_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.personal_atlas_index_selection_self_api_v1() to service_role;

create or replace function public.personal_atlas_index_selection_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.personal_atlas_index_selection_self_api_v1();
$function$;

revoke all on function public.personal_atlas_index_selection_self_api_v1() from public,anon;
grant execute on function public.personal_atlas_index_selection_self_api_v1() to authenticated,service_role;

create or replace function atlas.set_personal_atlas_index_selection_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_source_action_id text;
  v_categories jsonb;
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
    raise exception 'Index selection input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then raise exception 'sourceActionId required.' using errcode='22023'; end if;

  if coalesce(jsonb_typeof(p_input->'selectedCategories'),'array')<>'array' then
    raise exception 'selectedCategories must be an array.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(category) order by sort_key),'[]'::jsonb)
  into v_categories
  from (
    select distinct trim(value) as category,
      case trim(value)
        when 'home' then 10
        when 'family' then 20
        when 'job' then 30
        when 'business' then 40
        when 'property' then 50
        when 'money' then 60
        when 'school' then 70
        when 'projects' then 80
        when 'community' then 90
        when 'hobbies' then 100
        else 999
      end as sort_key
    from jsonb_array_elements_text(coalesce(p_input->'selectedCategories','[]'::jsonb))
    where nullif(trim(value),'') is not null
  ) s;

  if exists(
    select 1
    from jsonb_array_elements_text(v_categories) d(value)
    where d.value not in ('home','family','job','business','property','money','school','projects','community','hobbies')
  ) then
    raise exception 'Unsupported Index category.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.reality_discovery_orientation_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;

  if v_existing.id is not null then
    if v_existing.orientation_version<>4
       or v_existing.world_domains is distinct from v_categories
       or coalesce(v_existing.position_map,'{}'::jsonb)<>'{}'::jsonb
       or coalesce(v_existing.scale_map,'{}'::jsonb)<>'{}'::jsonb then
      raise exception 'sourceActionId already belongs to different Index evidence.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'idempotentReplay',true,
      'selection',atlas.personal_atlas_index_selection_self_api_v1(),
      'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  insert into atlas.reality_discovery_orientation_events(
    principal_id,owner_user_id,source_action_id,
    world_domains,carry_domains,position_map,scale_map,orientation_version,metadata
  ) values(
    v_principal_id,v_user_id,v_source_action_id,
    v_categories,'[]'::jsonb,'{}'::jsonb,'{}'::jsonb,4,
    jsonb_build_object(
      'source','first_encounter_index_selection_v1',
      'model','index_categories',
      'selectionDoesNotEstablishDomainTruth',true
    )
  )
  returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_personal_atlas_index_selection_self_api_v1',
    'eventId',v_event.id,
    'selection',atlas.personal_atlas_index_selection_self_api_v1(),
    'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'selectedCategoriesAreIntentionalNotebookStructure',true,
      'selectionDoesNotAnswerDiscoveryQuestions',true,
      'selectionDoesNotEstablishRoleOrScale',true
    )
  );
end;
$function$;

revoke all on function atlas.set_personal_atlas_index_selection_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.set_personal_atlas_index_selection_self_api_v1(jsonb) to service_role;

create or replace function public.set_personal_atlas_index_selection_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_personal_atlas_index_selection_self_api_v1(p_input);
$function$;

revoke all on function public.set_personal_atlas_index_selection_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_personal_atlas_index_selection_self_api_v1(jsonb) to authenticated,service_role;

-- The discovery profile now prefers explicit Index selection (v4). Prior v3
-- FIELD/POSITION/SCALE evidence remains historical fallback until the human
-- confirms the new Index.
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
    and orientation_version in (4,3)
  order by orientation_version desc,occurred_at desc,id desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_orientation_profile_self_api_v1',
    'model',case when v_event.orientation_version=4 then 'index_categories' else 'field_position_scale' end,
    'captured',v_event.id is not null,
    'worldDomains',coalesce(v_event.world_domains,'[]'::jsonb),
    'positionMap',case when v_event.orientation_version=4 then '{}'::jsonb else coalesce(v_event.position_map,'{}'::jsonb) end,
    'scaleMap',case when v_event.orientation_version=4 then '{}'::jsonb else coalesce(v_event.scale_map,'{}'::jsonb) end,
    'occurredAt',v_event.occurred_at,
    'truthBoundary',jsonb_build_object(
      'orientationIsColdStartEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'indexSelectionOrganizesNotebook',v_event.orientation_version=4,
      'indexSelectionMayConstrainAndReorderDiscovery',v_event.orientation_version=4,
      'positionAndScaleAreNotRequiredOnboarding',v_event.orientation_version=4,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

create or replace function public.reality_discovery_orientation_profile_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_orientation_profile_self_api_v1();
$function$;

revoke all on function public.reality_discovery_orientation_profile_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_orientation_profile_self_api_v1() to authenticated,service_role;

-- Children can exist outside the household. Ask the Family section directly,
-- including NONE, rather than requiring the person to first identify a generic
-- PARENT position during onboarding.
update atlas.reality_discovery_questions
set options='[
  {"key":"none","label":"none"},
  {"key":"minor","label":"minor"},
  {"key":"adult","label":"adult"},
  {"key":"both","label":"both"}
]'::jsonb,
    metadata=(metadata - 'orientationPositionPairs') || jsonb_build_object(
      'orientationPositionPairs','[]'::jsonb,
      'indexCategory','family'
    ),
    reason_text='Establish whether children are part of this person''s Family section without implying household membership.',
    updated_at=now()
where question_key='family.children_stage';

delete from atlas.reality_discovery_edges
where question_key='family.children_stage'
  and signal_key='orientation.family_parent'
  and effect_kind='require';

-- First-day sets are constrained to the sections the human intentionally put
-- in their Index. The chosen subjectDomain is returned so the app can open the
-- actual notebook section before raising the Instrument.
create or replace function atlas.reality_discovery_question_set_for_encounter_self_api_v1(
  p_session_kind text,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_kind text;
  v_limit integer;
  v_ranked jsonb;
  v_context jsonb;
  v_question jsonb;
  v_question_key text;
  v_policy atlas.reality_discovery_encounter_admission%rowtype;
  v_metadata jsonb;
  v_admitted boolean;
  v_anchor_cluster text;
  v_cluster_label text;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_has_eligible boolean := false;
  v_deferred_count integer := 0;
  v_household_shape_known boolean := false;
  v_orientation_captured boolean := false;
  v_selection jsonb;
  v_selected_categories jsonb := '[]'::jsonb;
  v_index_captured boolean := false;
  v_subject_domain text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_kind:=coalesce(nullif(trim(p_session_kind),''),'first_day');
  if v_kind not in ('first_day','manual','micro') then
    raise exception 'Unsupported discovery encounter kind.' using errcode='22023';
  end if;

  v_limit:=least(5,greatest(1,coalesce(p_limit,4)));
  v_ranked:=atlas.reality_discovery_ranked_questions_self_api_v1();
  v_context:=v_ranked->'context';
  v_household_shape_known:=coalesce(v_context#>>'{signals,household.people_shape}','')<>'';
  v_orientation_captured:=coalesce((v_context#>>'{orientation,captured}')::boolean,false);

  v_selection:=atlas.personal_atlas_index_selection_self_api_v1();
  v_index_captured:=coalesce((v_selection->>'captured')::boolean,false);
  v_selected_categories:=coalesce(v_selection->'selectedCategories','[]'::jsonb);

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if v_kind='first_day'
       and v_index_captured
       and jsonb_typeof(v_metadata->'orientationWorldDomains')='array'
       and not exists(
         select 1
         from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') d(domain)
         where v_selected_categories ? d.domain
       ) then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    v_has_eligible:=true;

    v_admitted:=case
      when v_kind='manual' then true
      when v_kind='first_day' then v_policy.question_key is not null and v_policy.first_day_disposition='admit'
      else false
    end;

    if not v_admitted then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    if v_kind='first_day'
       and not v_orientation_captured
       and not v_household_shape_known
       and coalesce(nullif(v_metadata->>'encounterCluster',''),'general')<>'you_home' then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    v_anchor_cluster:=coalesce(nullif(v_metadata->>'encounterCluster',''),'general');
    v_cluster_label:=coalesce(
      nullif(v_metadata->>'encounterClusterLabel',''),
      upper(replace(v_anchor_cluster,'_',' '))
    );
    exit;
  end loop;

  if v_anchor_cluster is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','reality_discovery_question_set_v4',
      'encounterKind',v_kind,
      'clusterKey',null,
      'clusterLabel',null,
      'items','[]'::jsonb,
      'quiet',true,
      'message','I know enough here for now.',
      'eligibleUnansweredRemain',v_has_eligible,
      'deferredCount',v_deferred_count,
      'context',v_context,
      'truthBoundary',jsonb_build_object(
        'quietMeansNoQuestionSetAdmittedForThisEncounter',true,
        'quietDoesNotMeanDiscoveryComplete',true,
        'indexSelectionConstrainsFirstDayQuestions',v_index_captured,
        'setIsPresentationGroupingNotTruth',true,
        'setRecomputesAfterEveryAnswer',true,
        'microAdmissionRequiresSeparateWarrant',true
      )
    );
  end if;

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if v_kind='first_day'
       and v_index_captured
       and jsonb_typeof(v_metadata->'orientationWorldDomains')='array'
       and not exists(
         select 1
         from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') d(domain)
         where v_selected_categories ? d.domain
       ) then
      continue;
    end if;

    v_admitted:=case
      when v_kind='manual' then true
      when v_kind='first_day' then v_policy.question_key is not null and v_policy.first_day_disposition='admit'
      else false
    end;

    if not v_admitted then continue; end if;
    if coalesce(nullif(v_metadata->>'encounterCluster',''),'general') is distinct from v_anchor_cluster then
      continue;
    end if;

    v_subject_domain:=null;
    if v_index_captured and jsonb_typeof(v_metadata->'orientationWorldDomains')='array' then
      select d.domain into v_subject_domain
      from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') with ordinality d(domain,ordinal)
      where v_selected_categories ? d.domain
      order by d.ordinal
      limit 1;
    end if;

    v_question:=atlas.reality_discovery_apply_option_eligibility_v1(v_question,v_context);

    v_items:=v_items||jsonb_build_array(
      v_question||jsonb_build_object(
        'admissionClass',coalesce(v_policy.admission_class,'unclassified'),
        'admissionReason',coalesce(v_policy.reason_text,'The human explicitly opened broader Discovery.'),
        'encounterCluster',v_anchor_cluster,
        'encounterClusterLabel',v_cluster_label,
        'subjectDomain',v_subject_domain
      )
    );
    v_count:=v_count+1;
    exit when v_count>=v_limit;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_question_set_v4',
    'encounterKind',v_kind,
    'clusterKey',v_anchor_cluster,
    'clusterLabel',v_cluster_label,
    'items',v_items,
    'quiet',false,
    'eligibleUnansweredRemain',v_has_eligible,
    'deferredCount',v_deferred_count,
    'context',v_context,
    'truthBoundary',jsonb_build_object(
      'setContainsOnlyCurrentlyEligibleAdmittedQuestions',true,
      'indexSelectionConstrainsFirstDayQuestions',v_index_captured,
      'questionCarriesNotebookSubjectDomain',true,
      'setIsPresentationGroupingNotTruth',true,
      'setRecomputesAfterEveryAnswer',true,
      'answeringOneItemMayRemoveOrReplaceOthers',true,
      'optionEligibilityUsesEstablishedContextOnly',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

-- The real Index contains the inside Bookplate plus intentional section roots.
-- Section-root existence is notebook organization only; it does not create source truth.
create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_selection jsonb;
  v_categories jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;

  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_selection:=atlas.personal_atlas_index_selection_self_api_v1();
  if coalesce((v_selection->>'captured')::boolean,false) then
    v_categories:=coalesce(v_selection->'selectedCategories','[]'::jsonb);
  end if;

  with descriptors as (
    select -10 as section_order,0 as item_order,
      jsonb_build_object(
        'addressKind','bookplate','spreadKey','bookplate','templateKey','bookplate',
        'title','Bookplate','section','Notebook',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','person','id',v_principal_id)
      ) as item
    union all
    select 0,0,
      jsonb_build_object('addressKind','today','spreadKey','today','templateKey','today','title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','day','id',current_date::text))
    union all
    select 0,1,
      jsonb_build_object('addressKind','index','spreadKey','index','templateKey','index','title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','notebook','id',v_user_id))
    union all
    select 5,
      case d.category
        when 'home' then 10
        when 'family' then 20
        when 'job' then 30
        when 'business' then 40
        when 'property' then 50
        when 'money' then 60
        when 'school' then 70
        when 'projects' then 80
        when 'community' then 90
        when 'hobbies' then 100
        else 999
      end,
      jsonb_build_object(
        'addressKind','section',
        'spreadKey','section:'||d.category,
        'templateKey','section-root',
        'title',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'section',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('domain',d.category,'kind','section','id',d.category),
        'intentionalSectionRoot',true
      )
    from jsonb_array_elements_text(v_categories) d(category)
    union all
    select 10,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey',s.spread_key,'templateKey','composed',
        'title',s.title,'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'spreadInstanceId',s.id,'spreadState',s.spread_state,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'purposeKey',s.purpose_key,'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb)
  into v_items
  from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,
      'indexDoesNotGrantAccess',true,
      'bookplateIsHumanEditableContactPresentation',true,
      'selectedSectionRootsAreIntentionalOrganizationNotDomainTruth',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,
      'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,
      'closedSpreadsRemainRetrievable',true,
      'dataBearingPagesComeFromDurableSpreadRegistry',true
    )
  );
end;
$function$;

create or replace function public.atlas_notebook_index_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.atlas_notebook_index_self_api_v1();
$function$;

revoke all on function public.atlas_notebook_index_self_api_v1() from public,anon;
grant execute on function public.atlas_notebook_index_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
(
  'atlas.personal_atlas_bookplate_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,3,0,
  jsonb_build_object(
    'purpose','Read editable inside-cover contact presentation and preserve the underlying purchase/auth evidence boundary.',
    'truthBoundary','Bookplate values are human-correctable and never rewrite source evidence or residence truth.'
  ),now()
),
(
  'atlas.set_personal_atlas_bookplate_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,3,0,
  jsonb_build_object(
    'purpose','Establish or correct the Personal Atlas Bookplate while preserving source provenance.',
    'truthBoundary','Preferred contact values do not mutate authentication or purchase evidence; contact address is not residence.'
  ),now()
),
(
  'atlas.personal_atlas_index_selection_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,2,0,
  jsonb_build_object(
    'purpose','Read the human-selected Personal Atlas Index categories.',
    'truthBoundary','Index selection organizes attention and notebook structure without establishing domain facts.'
  ),now()
),
(
  'atlas.set_personal_atlas_index_selection_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append the human-selected Personal Atlas Index categories.',
    'truthBoundary','Selection may constrain Discovery but never answers role, scale, ownership, or topology questions.'
  ),now()
),
(
  'atlas.reality_discovery_orientation_profile_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Expose current cold-start orientation, preferring intentional Index selection over superseded FIELD/POSITION/SCALE onboarding.',
    'truthBoundary','Selected Index categories organize the notebook and Discovery attention only.'
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
  caller_count=excluded.caller_count,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();

commit;
