create or replace function atlas.current_person_id_v1()
returns uuid
language sql
stable
security definer
set search_path to 'pg_catalog', 'auth', 'reality'
as $function$
  select b.person_entity_id
  from reality.auth_person_bindings b
  join reality.entities e
    on e.id=b.person_entity_id
   and e.entity_kind='person'
   and e.identity_state='canonical'
  where b.auth_user_id=auth.uid()
    and b.binding_state='active'
    and b.retired_at is null
  order by b.bound_at desc,b.id
  limit 1;
$function$;

create or replace function atlas.reality_access_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth', 'reality', 'personal', 'ledger', 'compatibility'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_claims jsonb:=auth.jwt();
  v_session_id uuid;
  v_email text;
  v_person reality.entities%rowtype;
  v_personal personal.atlases%rowtype;
  v_seats jsonb:='[]'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object(
      'contractVersion','reality_access_self_v1',
      'authenticated',false,
      'state','anonymous',
      'ledgerSeats','[]'::jsonb
    );
  end if;

  begin
    v_session_id:=nullif(v_claims->>'session_id','')::uuid;
  exception when others then
    v_session_id:=null;
  end;

  if v_session_id is null or not exists(
    select 1
    from auth.sessions s
    where s.id=v_session_id
      and s.user_id=v_uid
      and (s.not_after is null or s.not_after>now())
  ) then
    return jsonb_build_object(
      'contractVersion','reality_access_self_v1',
      'authenticated',false,
      'state','session_invalid',
      'ledgerSeats','[]'::jsonb
    );
  end if;

  select u.email
  into v_email
  from auth.users u
  where u.id=v_uid
    and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<=now());

  if not found then
    return jsonb_build_object(
      'contractVersion','reality_access_self_v1',
      'authenticated',false,
      'state','account_unavailable',
      'ledgerSeats','[]'::jsonb
    );
  end if;

  select e.*
  into v_person
  from reality.auth_person_bindings b
  join reality.entities e
    on e.id=b.person_entity_id
   and e.entity_kind='person'
   and e.identity_state='canonical'
  where b.auth_user_id=v_uid
    and b.binding_state='active'
    and b.retired_at is null
  order by b.bound_at desc,b.id
  limit 1;

  if v_person.id is null then
    return jsonb_build_object(
      'contractVersion','reality_access_self_v1',
      'authenticated',true,
      'state','person_binding_required',
      'user',jsonb_build_object('id',v_uid,'email',v_email),
      'ledgerSeats','[]'::jsonb
    );
  end if;

  select a.*
  into v_personal
  from personal.atlases a
  where a.person_entity_id=v_person.id
    and a.atlas_state='active'
    and a.native
  order by a.created_at,a.id
  limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'seatId',s.id,
        'seatState',s.seat_state,
        'beganAt',s.began_at,
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerState',l.ledger_state,
        'subjectEntity',jsonb_build_object(
          'id',subject.id,
          'stableKey',subject.stable_key,
          'kind',subject.entity_kind,
          'displayName',subject.display_name,
          'identityState',subject.identity_state
        ),
        'legacyOperationalCompatibility',case
          when compat.legacy_organization_id is null then null
          else jsonb_build_object(
            'organizationId',compat.legacy_organization_id,
            'meaning','routing_only_not_identity_or_authority'
          )
        end
      )
      order by l.name,l.id,s.id
    ),
    '[]'::jsonb
  )
  into v_seats
  from ledger.seats s
  join ledger.ledgers l
    on l.id=s.ledger_id
   and l.ledger_state='active'
   and l.retired_at is null
  join reality.entities subject
    on subject.id=l.subject_entity_id
   and subject.identity_state='canonical'
  left join lateral (
    select b.legacy_key as legacy_organization_id
    from compatibility.legacy_bindings b
    where b.legacy_schema='atlas'
      and b.legacy_table='organizations'
      and b.disposition='maps_to'
      and b.new_schema='reality'
      and b.new_table='entities'
      and b.new_id=subject.id
    order by b.created_at,b.id
    limit 1
  ) compat on true
  where s.person_entity_id=v_person.id
    and s.seat_state='active'
    and s.ended_at is null;

  if v_personal.id is null then
    return jsonb_build_object(
      'contractVersion','reality_access_self_v1',
      'authenticated',true,
      'state','personal_atlas_required',
      'user',jsonb_build_object('id',v_uid,'email',v_email),
      'person',jsonb_build_object(
        'id',v_person.id,
        'stableKey',v_person.stable_key,
        'kind',v_person.entity_kind,
        'displayName',v_person.display_name,
        'identityState',v_person.identity_state
      ),
      'ledgerSeats',v_seats
    );
  end if;

  return jsonb_build_object(
    'contractVersion','reality_access_self_v1',
    'authenticated',true,
    'state','ready',
    'user',jsonb_build_object('id',v_uid,'email',v_email),
    'person',jsonb_build_object(
      'id',v_person.id,
      'stableKey',v_person.stable_key,
      'kind',v_person.entity_kind,
      'displayName',v_person.display_name,
      'identityState',v_person.identity_state
    ),
    'personalAtlas',jsonb_build_object(
      'id',v_personal.id,
      'personEntityId',v_personal.person_entity_id,
      'state',v_personal.atlas_state,
      'native',v_personal.native
    ),
    'ledgerSeats',v_seats,
    'truthBoundary',jsonb_build_object(
      'authBindsDirectlyToRealityPerson',true,
      'personalAtlasIsNotLedger',true,
      'seatMeansParticipationOnly',true,
      'seatDoesNotEstablishOwnership',true,
      'legacyOrganizationIdIsRoutingOnly',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_access_self_api_v1() from public,anon;
grant execute on function atlas.reality_access_self_api_v1() to authenticated,service_role;

create or replace function atlas.current_session_context_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_access jsonb;
  v_uid uuid;
  v_profile jsonb;
  v_farm_memberships jsonb:='[]'::jsonb;
  v_compat_org_ids jsonb:='[]'::jsonb;
begin
  v_access:=atlas.reality_access_self_api_v1();

  if coalesce((v_access->>'authenticated')::boolean,false)=false then
    return v_access || jsonb_build_object(
      'contractVersion','current_session_context_v2',
      'memberships','[]'::jsonb,
      'compatibilityOrganizationIds','[]'::jsonb
    );
  end if;

  v_uid:=(v_access->'user'->>'id')::uuid;

  select jsonb_build_object(
    'user_id',p.user_id,
    'display_name',coalesce(v_access->'person'->>'displayName',p.display_name),
    'default_farm_id',p.default_farm_id,
    'active',true
  )
  into v_profile
  from atlas.user_profiles p
  where p.user_id=v_uid;

  if v_profile is null then
    v_profile:=jsonb_build_object(
      'user_id',v_uid,
      'display_name',coalesce(v_access->'person'->>'displayName',v_access->'user'->>'email'),
      'default_farm_id',null,
      'active',true
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',m.id,
        'farm_id',m.farm_id,
        'role',m.role,
        'worker_key',m.worker_key,
        'active',m.active,
        'permissions',coalesce(m.permissions,'{}'::jsonb),
        'farm',jsonb_build_object(
          'id',f.id,
          'stable_key',f.stable_key,
          'name',f.name,
          'status',f.status
        )
      )
      order by m.id
    ),
    '[]'::jsonb
  )
  into v_farm_memberships
  from atlas.farm_memberships m
  join atlas.farms f on f.id=m.farm_id
  where m.user_id=v_uid
    and m.active
    and f.status='active';

  select coalesce(jsonb_agg(q.organization_id order by q.organization_id),'[]'::jsonb)
  into v_compat_org_ids
  from (
    select distinct item->'legacyOperationalCompatibility'->>'organizationId' as organization_id
    from jsonb_array_elements(coalesce(v_access->'ledgerSeats','[]'::jsonb)) item
    where nullif(item->'legacyOperationalCompatibility'->>'organizationId','') is not null
  ) q;

  return v_access || jsonb_build_object(
    'contractVersion','current_session_context_v2',
    'profile',v_profile,
    'memberships',v_farm_memberships,
    'compatibilityOrganizationIds',v_compat_org_ids,
    'operationalCompatibilityBoundary',jsonb_build_object(
      'farmMembershipsRemainExecutionScope',true,
      'organizationIdsAreRoutingOnly',true,
      'organizationMembershipsAreNotIdentityOrAccessTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.current_session_context_api_v2() from public,anon;
grant execute on function atlas.current_session_context_api_v2() to authenticated,service_role;

create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_access jsonb;
begin
  v_access:=atlas.reality_access_self_api_v1();

  if coalesce((v_access->>'authenticated')::boolean,false)=false then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if coalesce(v_access->>'state','')<>'ready' then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v4',
      'state',v_access->>'state',
      'personEntityId',v_access->'person'->>'id',
      'personalAtlasId',v_access->'personalAtlas'->>'id',
      'items','[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v4',
    'state','ready',
    'personEntityId',v_access->'person'->>'id',
    'personalAtlasId',v_access->'personalAtlas'->>'id',
    'items',coalesce(v_access->'ledgerSeats','[]'::jsonb),
    'accessSemantics','ledger_seat_participation',
    'truthBoundary',jsonb_build_object(
      'principalLedgerAuthorityRetired',true,
      'seatDoesNotEstablishOwnership',true,
      'seatDoesNotEstablishEntityAuthority',true
    )
  );
end;
$function$;

revoke all on function atlas.principal_ledgers_self_api_v1() from public,anon;
grant execute on function atlas.principal_ledgers_self_api_v1() to authenticated;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_access jsonb;
  v_base jsonb;
begin
  v_access:=atlas.reality_access_self_api_v1();

  if coalesce((v_access->>'authenticated')::boolean,false)=false then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  if coalesce(v_access->>'state','')<>'ready' then
    return jsonb_build_object(
      'contractVersion','principal_self_context_v5',
      'state',v_access->>'state',
      'realityPerson',v_access->'person',
      'personalAtlas',v_access->'personalAtlas',
      'ledgerSeats',coalesce(v_access->'ledgerSeats','[]'::jsonb)
    );
  end if;

  v_base:=atlas.principal_self_context_physical_compatibility_internal_v1();

  return v_base || jsonb_build_object(
    'contractVersion','principal_self_context_v5',
    'realityPerson',v_access->'person',
    'personalAtlas',v_access->'personalAtlas',
    'ledgerSeats',coalesce(v_access->'ledgerSeats','[]'::jsonb),
    'identityRoot','reality_person',
    'ledgerAccessRoot','ledger_seats',
    'legacyPrincipalSemantics','compatibility_data_carrier_only',
    'truthBoundary',coalesce(v_access->'truthBoundary','{}'::jsonb) || jsonb_build_object(
      'principalDoesNotEstablishIdentity',true,
      'principalLedgerAuthorityNotUsedForReadAccess',true
    )
  );
end;
$function$;

revoke all on function atlas.principal_self_context_api_v1() from public,anon;
grant execute on function atlas.principal_self_context_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.reality_access_self_api_v1()','app_endpoint','verified','active',
  true,true,true,1,0,
  jsonb_build_object(
    'purpose','Resolve signed-in Atlas identity and Ledger participation from Reality / Personal Atlas / Ledger core.',
    'boundary','Auth credential binds directly to canonical Reality Person; Seats establish participation only; legacy organization IDs are routing-only compatibility metadata.',
    'forbiddenAuthoritySources',jsonb_build_array('atlas.organization_memberships','atlas.principal_ledger_authorities')
  ),
  now(),false
),
(
  'atlas.current_session_context_api_v2()','app_endpoint','verified','active',
  true,true,true,1,0,
  jsonb_build_object(
    'purpose','Hydrate the application session from canonical Reality access plus farm execution compatibility.',
    'boundary','Farm memberships remain operational execution scope; organization memberships do not establish identity or session activation.'
  ),
  now(),false
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

update atlas.authenticated_rpc_registry
set evidence=evidence || jsonb_build_object(
      'identityRoot','reality.auth_person_bindings -> reality.entities(person)',
      'legacyPrincipalSemantics','compatibility data carrier only',
      'principalLedgerAuthorityUsedForReadAccess',false
    ),
    reviewed_at=now()
where signature='atlas.principal_self_context_api_v1()';

comment on function atlas.current_person_id_v1() is
  'Compatibility-named current Person resolver. Canonical identity source is Reality Auth→Person binding; legacy person_auth_credentials no longer identify the signed-in Person.';

comment on function atlas.current_principal_id_v1() is
  'Compatibility data-carrier locator only. It resolves the legacy Principal attached to the already-canonical Reality Person and must not be used as identity or Ledger authority truth.';

comment on function atlas.reality_access_self_api_v1() is
  'Canonical authenticated Atlas read-access membrane: Auth→Reality Person→native Personal Atlas / active Ledger Seats→Ledgers. Seats mean participation only.';

comment on function atlas.current_session_context_api_v2() is
  'Canonical Atlas session projection. Identity/access comes from Reality and Ledger Seats; farm memberships are carried only for operational execution compatibility.';

comment on function atlas.principal_ledgers_self_api_v1() is
  'Legacy-named read endpoint now projecting active Ledger Seats. It no longer reads Principal Ledger Authority; Seat participation does not imply ownership or Entity authority.';

comment on function atlas.principal_self_context_api_v1() is
  'Principal OS read projection rooted in canonical Reality Person. Legacy Principal remains a compatibility carrier for existing personal operating data, not identity or Ledger authority.';

do $validation$
begin
  if pg_get_functiondef('atlas.current_person_id_v1()'::regprocedure) ilike '%person_auth_credentials%' then
    raise exception 'Current Person still depends on legacy person_auth_credentials.';
  end if;
  if pg_get_functiondef('atlas.reality_access_self_api_v1()'::regprocedure) ilike '%organization_memberships%'
     or pg_get_functiondef('atlas.reality_access_self_api_v1()'::regprocedure) ilike '%principal_ledger_authorities%' then
    raise exception 'Reality access membrane depends on retired identity/authority structures.';
  end if;
  if pg_get_functiondef('atlas.principal_ledgers_self_api_v1()'::regprocedure) ilike '%principal_ledger_authorities%' then
    raise exception 'Principal Ledger read path still depends on Principal Ledger Authority.';
  end if;
  if pg_get_functiondef('atlas.principal_self_context_api_v1()'::regprocedure) ilike '%principal_ledger_authorities%' then
    raise exception 'Principal self read path still depends on Principal Ledger Authority.';
  end if;
end
$validation$;
