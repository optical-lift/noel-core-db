create table reality.responsibility_relations (
  id uuid primary key default gen_random_uuid(),
  carrier_person_entity_id uuid not null references reality.entities(id) on delete restrict,
  responsibility_key text not null check (btrim(responsibility_key)<>''),
  title text not null check (btrim(title)<>''),
  relation_state text not null default 'active'
    check (relation_state in ('active','paused','ended')),
  jurisdiction_kind text not null
    check (jurisdiction_kind in ('entity','domain')),
  jurisdiction_entity_id uuid null references reality.entities(id) on delete restrict,
  jurisdiction_domain text null,
  permitted_operations text[] not null,
  scope jsonb not null default '{}'::jsonb
    check (jsonb_typeof(scope)='object'),
  establishment_kind text not null check (btrim(establishment_kind)<>''),
  source_person_entity_id uuid null references reality.entities(id) on delete restrict,
  establishment_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(establishment_basis)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(permitted_operations)>0),
  check (
    (jurisdiction_kind='entity'
      and jurisdiction_entity_id is not null
      and jurisdiction_domain is null)
    or
    (jurisdiction_kind='domain'
      and jurisdiction_entity_id is null
      and jurisdiction_domain is not null
      and btrim(jurisdiction_domain)<>'')
  ),
  check (ended_at is null or ended_at>=began_at)
);

create unique index reality_responsibility_active_entity_idx
  on reality.responsibility_relations(
    carrier_person_entity_id,responsibility_key,jurisdiction_entity_id
  )
  where relation_state='active' and jurisdiction_kind='entity';

create unique index reality_responsibility_active_domain_idx
  on reality.responsibility_relations(
    carrier_person_entity_id,responsibility_key,jurisdiction_domain
  )
  where relation_state='active' and jurisdiction_kind='domain';

create index reality_responsibility_carrier_idx
  on reality.responsibility_relations(
    carrier_person_entity_id,relation_state,responsibility_key
  );

alter table reality.responsibility_relations enable row level security;
revoke all on table reality.responsibility_relations from public,anon,authenticated;
grant select,insert,update,delete on table reality.responsibility_relations to service_role;

create or replace function reality.guard_responsibility_relation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_ops text[];
begin
  perform reality.assert_person_entity_v1(new.carrier_person_entity_id);

  if new.source_person_entity_id is not null then
    perform reality.assert_person_entity_v1(new.source_person_entity_id);
  end if;

  if new.jurisdiction_kind='entity' then
    if not exists(
      select 1
      from reality.entities e
      where e.id=new.jurisdiction_entity_id
        and e.identity_state<>'retired'
    ) then
      raise exception 'Active jurisdiction Entity required.' using errcode='23514';
    end if;
  end if;

  select array_agg(distinct btrim(op) order by btrim(op))
  into v_ops
  from unnest(coalesce(new.permitted_operations,'{}'::text[])) op
  where btrim(op)<>'';

  if coalesce(cardinality(v_ops),0)=0 then
    raise exception 'At least one nonblank permitted operation is required.'
      using errcode='23514';
  end if;

  new.permitted_operations:=v_ops;

  if new.relation_state='ended' and new.ended_at is null then
    new.ended_at:=now();
  end if;

  if new.relation_state<>'ended' and new.ended_at is not null then
    raise exception 'Only an ended responsibility relation may have ended_at.'
      using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger reality_responsibility_relations_guard_v1
before insert or update on reality.responsibility_relations
for each row execute function reality.guard_responsibility_relation_v1();

create or replace function reality.resolve_responsibility_relation_v1(
  p_person_entity_id uuid,
  p_responsibility_key text,
  p_operation_key text,
  p_jurisdiction_kind text,
  p_jurisdiction_entity_id uuid default null,
  p_jurisdiction_domain text default null,
  p_required_scope jsonb default '{}'::jsonb
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select rr.id
  from reality.responsibility_relations rr
  join reality.entities person
    on person.id=rr.carrier_person_entity_id
   and person.entity_kind='person'
   and person.identity_state='canonical'
  left join reality.entities subject
    on subject.id=rr.jurisdiction_entity_id
  where rr.carrier_person_entity_id=p_person_entity_id
    and rr.responsibility_key=p_responsibility_key
    and rr.relation_state='active'
    and rr.began_at<=now()
    and rr.ended_at is null
    and p_operation_key=any(rr.permitted_operations)
    and rr.jurisdiction_kind=p_jurisdiction_kind
    and (
      (p_jurisdiction_kind='entity'
        and rr.jurisdiction_entity_id=p_jurisdiction_entity_id
        and subject.identity_state='canonical')
      or
      (p_jurisdiction_kind='domain'
        and rr.jurisdiction_domain=p_jurisdiction_domain)
    )
    and rr.scope @> coalesce(p_required_scope,'{}'::jsonb)
  order by rr.began_at desc,rr.id
  limit 1;
$function$;

revoke all on function reality.resolve_responsibility_relation_v1(
  uuid,text,text,text,uuid,text,jsonb
) from public,anon,authenticated;

create or replace function atlas.current_responsibility_context_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','current_responsibility_context_v1',
      'state','person_binding_required',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'relationId',rr.id,
        'responsibilityKey',rr.responsibility_key,
        'title',rr.title,
        'jurisdiction',case
          when rr.jurisdiction_kind='entity' then
            jsonb_build_object(
              'kind','entity',
              'entityId',rr.jurisdiction_entity_id,
              'entityStableKey',subject.stable_key,
              'entityKind',subject.entity_kind,
              'entityDisplayName',subject.display_name
            )
          else
            jsonb_build_object(
              'kind','domain',
              'domain',rr.jurisdiction_domain
            )
        end,
        'permittedOperations',to_jsonb(rr.permitted_operations),
        'scope',rr.scope,
        'beganAt',rr.began_at
      )
      order by rr.responsibility_key,
               rr.jurisdiction_kind,
               coalesce(subject.stable_key,rr.jurisdiction_domain),
               rr.id
    ),
    '[]'::jsonb
  )
  into v_items
  from reality.responsibility_relations rr
  left join reality.entities subject
    on subject.id=rr.jurisdiction_entity_id
  where rr.carrier_person_entity_id=v_person_id
    and rr.relation_state='active'
    and rr.began_at<=now()
    and rr.ended_at is null
    and (
      rr.jurisdiction_kind='domain'
      or subject.identity_state='canonical'
    );

  return jsonb_build_object(
    'contractVersion','current_responsibility_context_v1',
    'state','ready',
    'personEntityId',v_person_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'seatDoesNotGrantResponsibility',true,
      'roleDoesNotGrantResponsibility',true,
      'responsibilityDoesNotGrantUnlistedOperations',true,
      'jurisdictionIsMandatory',true
    )
  );
end
$function$;

revoke all on function atlas.current_responsibility_context_self_api_v1()
  from public,anon;
grant execute on function atlas.current_responsibility_context_self_api_v1()
  to authenticated,service_role;

create or replace function atlas.current_session_context_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_access jsonb;
  v_uid uuid;
  v_profile jsonb;
  v_farm_memberships jsonb:='[]'::jsonb;
  v_compat_org_ids jsonb:='[]'::jsonb;
  v_responsibilities jsonb:='[]'::jsonb;
begin
  v_access:=atlas.reality_access_self_api_v1();

  if coalesce((v_access->>'authenticated')::boolean,false)=false then
    return v_access || jsonb_build_object(
      'contractVersion','current_session_context_v2',
      'memberships','[]'::jsonb,
      'compatibilityOrganizationIds','[]'::jsonb,
      'responsibilities','[]'::jsonb
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

  if coalesce(v_access->>'state','')='ready' then
    v_responsibilities:=coalesce(
      atlas.current_responsibility_context_self_api_v1()->'items',
      '[]'::jsonb
    );
  end if;

  return v_access || jsonb_build_object(
    'contractVersion','current_session_context_v2',
    'profile',v_profile,
    'memberships',v_farm_memberships,
    'compatibilityOrganizationIds',v_compat_org_ids,
    'responsibilities',v_responsibilities,
    'operationalCompatibilityBoundary',jsonb_build_object(
      'farmMembershipsRemainExecutionScope',true,
      'organizationIdsAreRoutingOnly',true,
      'organizationMembershipsAreNotIdentityOrAccessTruth',true,
      'rolesDoNotGrantRealityResponsibility',true
    )
  );
end
$function$;

create or replace function atlas.reality_entity_for_legacy_farm_internal_v1(
  p_farm_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select lb.new_id
  from atlas.farms f
  join compatibility.legacy_bindings lb
    on lb.legacy_schema='atlas'
   and lb.legacy_table='organizations'
   and lb.legacy_key=f.organization_id::text
   and lb.disposition='maps_to'
   and lb.new_schema='reality'
   and lb.new_table='entities'
  join reality.entities e
    on e.id=lb.new_id
   and e.identity_state='canonical'
  where f.id=p_farm_id
    and f.status='active'
  order by lb.created_at,lb.id
  limit 1;
$function$;

revoke all on function atlas.reality_entity_for_legacy_farm_internal_v1(uuid)
  from public,anon,authenticated;

create or replace function atlas.entity_identity_review_queue_api_v2()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel','auth','reality','pg_temp'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_any_relation uuid;
  v_items jsonb;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_any_relation:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_adjudication',
    'identity_review.read',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  );

  if v_any_relation is null then
    raise exception 'Reality identity adjudication responsibility required.'
      using errcode='42501';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.recommended_at,q.review_kind,q.review_id),
    '[]'::jsonb
  )
  into v_items
  from local_intel.v_entity_identity_review_queue_v2 q
  where reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_adjudication',
    'identity_review.read',
    'domain',
    null,
    'reality.identity_resolution',
    jsonb_build_object('reviewKinds',jsonb_build_array(q.review_kind))
  ) is not null;

  return jsonb_build_object(
    'contractVersion','entity_identity_review_v2',
    'state',case when jsonb_array_length(v_items)=0 then 'clear' else 'review_required' end,
    'pendingCount',jsonb_array_length(v_items),
    'reviewerUserId',v_user_id,
    'reviewerPersonEntityId',v_person_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'humanAdjudicationRequired',true,
      'rawMutationExposed',false,
      'approvalIsCanonicalMergeExecution',false,
      'canonicalMergeExecutionAvailableHere',false,
      'authoritySource','reality_responsibility_relation'
    )
  );
end
$function$;

revoke all on function atlas.entity_identity_review_queue_api_v2()
  from public,anon;
grant execute on function atlas.entity_identity_review_queue_api_v2()
  to authenticated;

create or replace function atlas.entity_identity_adjudicate_api_v2(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel','auth','reality','pg_temp'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_relation_id uuid;
  v_review_kind text;
  v_review_id uuid;
  v_decision text;
  v_basis text;
  v_reviewer text;
  v_metadata jsonb;
  v_queue local_intel.v_entity_identity_review_queue_v2%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Review input must be a JSON object.' using errcode='22023';
  end if;
  if p_input ? 'metadata' then
    raise exception 'Caller-supplied adjudication metadata is not accepted.'
      using errcode='22023';
  end if;

  v_review_kind:=nullif(btrim(p_input->>'reviewKind'),'');
  v_decision:=nullif(btrim(p_input->>'decision'),'');
  v_basis:=nullif(btrim(p_input->>'basis'),'');

  begin
    v_review_id:=nullif(btrim(p_input->>'reviewId'),'')::uuid;
  exception when invalid_text_representation then
    raise exception 'A valid reviewId is required.' using errcode='22023';
  end;

  if v_review_id is null then
    raise exception 'A valid reviewId is required.' using errcode='22023';
  end if;
  if v_review_kind not in ('ingestion_candidate_match','entity_merge') then
    raise exception 'Unsupported reviewKind.' using errcode='22023';
  end if;
  if v_decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected.' using errcode='22023';
  end if;
  if v_basis is null then
    raise exception 'A reviewer basis is required.' using errcode='22023';
  end if;
  if length(v_basis)>4000 then
    raise exception 'Reviewer basis is too long.' using errcode='22023';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'reality_identity_adjudication',
    'identity_review.adjudicate',
    'domain',
    null,
    'reality.identity_resolution',
    jsonb_build_object('reviewKinds',jsonb_build_array(v_review_kind))
  );

  if v_relation_id is null then
    raise exception 'Reality identity adjudication responsibility required.'
      using errcode='42501';
  end if;

  select * into v_queue
  from local_intel.v_entity_identity_review_queue_v2 q
  where q.review_id=v_review_id
    and q.review_kind=v_review_kind;

  if not found then
    raise exception 'This review item is no longer pending.' using errcode='22023';
  end if;

  if v_review_kind='entity_merge'
     and v_decision='approved'
     and not coalesce(v_queue.approval_ready,false) then
    raise exception 'Merge approval is blocked by the hard-veto membrane.'
      using errcode='22023';
  end if;

  select e.display_name
  into v_reviewer
  from reality.entities e
  where e.id=v_person_id
    and e.entity_kind='person'
    and e.identity_state='canonical';

  v_reviewer:=coalesce(nullif(btrim(v_reviewer),''),v_person_id::text);

  v_metadata:=jsonb_build_object(
    'atlas_review_contract','entity_identity_review_v2',
    'authenticated_user_id',v_user_id,
    'reviewer_person_entity_id',v_person_id,
    'responsibility_relation_id',v_relation_id,
    'review_kind',v_review_kind,
    'review_id',v_review_id,
    'surface','principal_entity_identity_review_v2',
    'caller_metadata_accepted',false
  );

  if v_review_kind='ingestion_candidate_match' then
    v_result:=local_intel.adjudicate_entity_ingestion_match_v1(
      v_review_id,v_decision,v_reviewer,v_basis,v_metadata
    );
  else
    v_result:=local_intel.adjudicate_entity_merge_decision_v1(
      v_review_id,v_decision,v_reviewer,v_basis,v_metadata
    );
  end if;

  return jsonb_build_object(
    'contractVersion','entity_identity_review_v2',
    'reviewKind',v_review_kind,
    'reviewId',v_review_id,
    'decision',v_decision,
    'reviewerUserId',v_user_id,
    'reviewerPersonEntityId',v_person_id,
    'responsibilityRelationId',v_relation_id,
    'canonicalMergeExecuted',false,
    'result',v_result
  );
end
$function$;

revoke all on function atlas.entity_identity_adjudicate_api_v2(jsonb)
  from public,anon;
grant execute on function atlas.entity_identity_adjudicate_api_v2(jsonb)
  to authenticated;

create or replace function atlas.set_worker_day_shape_internal_v2(
  p_farm_id uuid,
  p_membership_id uuid,
  p_weekdays smallint[],
  p_local_start time,
  p_local_end time,
  p_effective_from date,
  p_reason text,
  p_actor_user_id uuid,
  p_authority_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_weekdays smallint[];
  v_version integer;
  v_policy_id uuid;
  v_policy_key text:='standard_worker_day';
  v_timezone text;
  v_today date;
  v_capacity_sync jsonb;
begin
  if p_actor_user_id is null then
    raise exception 'Actor user is required.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.farm_memberships fm
    where fm.id=p_membership_id
      and fm.farm_id=p_farm_id
      and fm.active=true
      and fm.role='farm_hand'
  ) then
    raise exception 'Active Farm Hand membership required.' using errcode='42501';
  end if;

  if p_effective_from is null or p_local_start is null or p_local_end is null then
    raise exception 'Effective date, local start, and local end are required.'
      using errcode='22023';
  end if;

  if p_local_end<=p_local_start then
    raise exception 'Worker Day end must be later than its start.' using errcode='22023';
  end if;

  select array_agg(distinct weekday order by weekday)
  into v_weekdays
  from unnest(coalesce(p_weekdays,'{}'::smallint[])) weekday
  where weekday between 0 and 6;

  if coalesce(cardinality(v_weekdays),0)=0
     or cardinality(v_weekdays)<>cardinality(coalesce(p_weekdays,'{}'::smallint[])) then
    raise exception 'Choose one or more unique weekdays from 0 through 6.'
      using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_membership_id::text||':worker-day-shape',0)
  );

  select coalesce(max(policy.version),0)+1
  into v_version
  from atlas.worker_day_shape_policies policy
  where policy.membership_id=p_membership_id
    and policy.policy_key=v_policy_key;

  update atlas.worker_day_shape_policies policy
  set effective_through=p_effective_from-1,
      updated_at=now()
  where policy.farm_id=p_farm_id
    and policy.membership_id=p_membership_id
    and policy.policy_key=v_policy_key
    and policy.active=true
    and policy.effective_from<p_effective_from
    and (policy.effective_through is null or policy.effective_through>=p_effective_from);

  update atlas.worker_day_shape_policies policy
  set active=false,
      updated_at=now(),
      metadata=coalesce(policy.metadata,'{}'::jsonb)||jsonb_build_object(
        'superseded_at',now(),
        'superseded_by_version',v_version
      )
  where policy.farm_id=p_farm_id
    and policy.membership_id=p_membership_id
    and policy.policy_key=v_policy_key
    and policy.active=true
    and policy.effective_from>=p_effective_from;

  insert into atlas.worker_day_shape_policies(
    farm_id,membership_id,policy_key,policy_name,version,weekdays,local_start,local_end,
    effective_from,active,authored_by_user_id,authored_reason,metadata
  ) values (
    p_farm_id,p_membership_id,v_policy_key,'Standard Worker Day',v_version,
    v_weekdays,p_local_start,p_local_end,p_effective_from,true,p_actor_user_id,
    nullif(btrim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'source','set_worker_day_shape_internal_v2',
      'authority',coalesce(p_authority_basis,'{}'::jsonb)
    )
  )
  returning id into v_policy_id;

  select coalesce(nullif(f.metadata->>'timezone',''),'UTC')
  into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;

  v_today:=(now() at time zone coalesce(v_timezone,'UTC'))::date;

  if p_effective_from<=v_today
     and to_regprocedure(
       'atlas.sync_worker_weekly_capacity_escalation_v1(uuid,uuid,date)'
     ) is not null then
    v_capacity_sync:=atlas.sync_worker_weekly_capacity_escalation_v1(
      p_farm_id,p_membership_id,v_today
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'policyId',v_policy_id,
    'policyVersion',v_version,
    'effective',atlas.worker_day_shape_effective_v1(
      p_farm_id,p_membership_id,p_effective_from
    ),
    'capacitySync',v_capacity_sync
  );
end
$function$;

revoke all on function atlas.set_worker_day_shape_internal_v2(
  uuid,uuid,smallint[],time,time,date,text,uuid,jsonb
) from public,anon,authenticated;

create or replace function atlas.owner_set_worker_day_shape_api_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_weekdays smallint[],
  p_local_start time,
  p_local_end time,
  p_effective_from date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  if not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Owner farm membership required.' using errcode='42501';
  end if;

  return atlas.set_worker_day_shape_internal_v2(
    p_farm_id,
    p_membership_id,
    p_weekdays,
    p_local_start,
    p_local_end,
    p_effective_from,
    p_reason,
    auth.uid(),
    jsonb_build_object(
      'authorityMode','legacy_farm_owner_compatibility',
      'legacyRole','owner'
    )
  );
end
$function$;

create or replace function atlas.institutional_worker_day_shape_set_self_api_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_weekdays smallint[],
  p_local_start time,
  p_local_end time,
  p_effective_from date,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_entity_id uuid;
  v_relation_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  v_entity_id:=atlas.reality_entity_for_legacy_farm_internal_v1(p_farm_id);
  if v_entity_id is null then
    raise exception 'Canonical Reality institution required for this farm.'
      using errcode='42501';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'institutional_worker_capacity_truth',
    'worker_day_shape.author',
    'entity',
    v_entity_id,
    null,
    jsonb_build_object('farmIds',jsonb_build_array(p_farm_id::text))
  );

  if v_relation_id is null then
    raise exception 'Institutional worker-capacity responsibility required.'
      using errcode='42501';
  end if;

  return atlas.set_worker_day_shape_internal_v2(
    p_farm_id,
    p_membership_id,
    p_weekdays,
    p_local_start,
    p_local_end,
    p_effective_from,
    p_reason,
    v_user_id,
    jsonb_build_object(
      'authorityMode','reality_responsibility_relation',
      'responsibilityRelationId',v_relation_id,
      'personEntityId',v_person_id,
      'institutionEntityId',v_entity_id
    )
  );
end
$function$;

revoke all on function atlas.institutional_worker_day_shape_set_self_api_v1(
  uuid,uuid,smallint[],time,time,date,text
) from public,anon;
grant execute on function atlas.institutional_worker_day_shape_set_self_api_v1(
  uuid,uuid,smallint[],time,time,date,text
) to authenticated;

with lex as (
  select id from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,
  responsibility_key,
  title,
  relation_state,
  jurisdiction_kind,
  jurisdiction_domain,
  permitted_operations,
  scope,
  establishment_kind,
  establishment_basis
)
select
  lex.id,
  'reality_identity_adjudication',
  'Adjudicate Reality identity recommendations',
  'active',
  'domain',
  'reality.identity_resolution',
  array['identity_review.adjudicate','identity_review.read']::text[],
  jsonb_build_object(
    'reviewKinds',
    jsonb_build_array('ingestion_candidate_match','entity_merge')
  ),
  'legacy_adjudicated_migration',
  jsonb_build_object(
    'basis','Existing human identity-review function was explicitly adjudicated into a bounded Reality responsibility.',
    'doesNotPreserve',jsonb_build_array('Principal','organization owner role','generic role'),
    'oldSurface','principal_entity_identity_review_v1'
  )
from lex
on conflict do nothing;

with lex as (
  select id from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical'
),
elm as (
  select id from reality.entities
  where stable_key='elm-farm'
    and identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,
  responsibility_key,
  title,
  relation_state,
  jurisdiction_kind,
  jurisdiction_entity_id,
  permitted_operations,
  scope,
  establishment_kind,
  establishment_basis
)
select
  lex.id,
  'institutional_worker_capacity_truth',
  'Establish worker capacity truth for Elm Farm',
  'active',
  'entity',
  elm.id,
  array['worker_day_shape.author','worker_day_shape.read_exception']::text[],
  jsonb_build_object(
    'farmIds',
    jsonb_build_array('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f')
  ),
  'legacy_adjudicated_migration',
  jsonb_build_object(
    'basis','Existing Farm Hand capacity exception function was explicitly adjudicated into bounded institutional responsibility.',
    'doesNotPreserve',jsonb_build_array('owner role','Principal','Seat ownership'),
    'legacyFarmStableKey','elm_farm'
  )
from lex,elm
on conflict do nothing;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.current_responsibility_context_self_api_v1()',
  'app_endpoint','verified','active',
  true,true,true,1,0,
  jsonb_build_object(
    'purpose','Return current bounded Reality responsibility relations for the signed-in Person.',
    'boundary','Responsibility is explicit and operation-scoped; Seat, Principal, organization membership, and generic role do not create it.'
  ),
  now(),false
),
(
  'atlas.entity_identity_review_queue_api_v2()',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Return identity review items within the signed-in Person''s Reality identity-adjudication responsibility.',
    'authority','reality.responsibility_relations'
  ),
  now(),false
),
(
  'atlas.entity_identity_adjudicate_api_v2(jsonb)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Adjudicate one identity review through an exact Reality responsibility and review-kind scope.',
    'authority','reality.responsibility_relations'
  ),
  now(),false
),
(
  'atlas.institutional_worker_day_shape_set_self_api_v1(uuid, uuid, smallint[], time without time zone, time without time zone, date, text)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Author one Farm Hand Day Shape through exact institutional worker-capacity responsibility.',
    'authority','reality.responsibility_relations',
    'jurisdiction','Reality Entity plus exact legacy farm scope'
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
      'includesRealityResponsibilities',true,
      'responsibilitySource','reality.responsibility_relations'
    ),
    reviewed_at=now()
where signature='atlas.current_session_context_api_v2()';

comment on table reality.responsibility_relations is
  'Explicit bounded responsibility relation: carrier Person + jurisdiction + permitted operation set. It must never be inferred from Seat participation, generic role, credential possession, or legacy ownership labels.';

comment on function reality.resolve_responsibility_relation_v1(
  uuid,text,text,text,uuid,text,jsonb
) is
  'Exact responsibility resolver. A relation authorizes only its listed operation inside its declared jurisdiction and scope.';

comment on function atlas.current_responsibility_context_self_api_v1() is
  'Authenticated projection of current Reality responsibilities. This is authority context, not identity, role, or Ledger participation.';

comment on function atlas.entity_identity_review_queue_api_v2() is
  'Identity review queue read through the explicit reality_identity_adjudication responsibility.';

comment on function atlas.entity_identity_adjudicate_api_v2(jsonb) is
  'Identity adjudication through exact Reality responsibility; approval remains separate from canonical merge execution.';

comment on function atlas.institutional_worker_day_shape_set_self_api_v1(
  uuid,uuid,smallint[],time,time,date,text
) is
  'Institution-scoped Worker Day Shape authoring through institutional_worker_capacity_truth responsibility; no owner role or Principal authority is consulted.';

do $validation$
declare
  v_lex uuid;
  v_elm uuid;
begin
  select id into v_lex from reality.entities where stable_key='lex';
  select id into v_elm from reality.entities where stable_key='elm-farm';

  if reality.resolve_responsibility_relation_v1(
    v_lex,'reality_identity_adjudication','identity_review.adjudicate',
    'domain',null,'reality.identity_resolution',
    jsonb_build_object('reviewKinds',jsonb_build_array('entity_merge'))
  ) is null then
    raise exception 'Lex identity adjudication responsibility did not resolve.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_lex,'reality_identity_adjudication','canonical_merge.execute',
    'domain',null,'reality.identity_resolution','{}'::jsonb
  ) is not null then
    raise exception 'Identity adjudication improperly grants canonical merge execution.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_lex,'institutional_worker_capacity_truth','worker_day_shape.author',
    'entity',v_elm,null,
    jsonb_build_object('farmIds',jsonb_build_array('6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'))
  ) is null then
    raise exception 'Elm worker capacity responsibility did not resolve.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_lex,'institutional_worker_capacity_truth','worker_day_shape.author',
    'entity',v_elm,null,
    jsonb_build_object('farmIds',jsonb_build_array('f6592422-cf2b-4375-ba8f-f00828a05c18'))
  ) is not null then
    raise exception 'Elm worker capacity responsibility leaked into Waiting Room Farm.';
  end if;

  if pg_get_functiondef(
       'atlas.entity_identity_adjudicate_api_v2(jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.entity_identity_adjudicate_api_v2(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
  then
    raise exception 'Identity v2 retains legacy authority semantics.';
  end if;

  if pg_get_functiondef(
       'atlas.institutional_worker_day_shape_set_self_api_v1(uuid,uuid,smallint[],time without time zone,time without time zone,date,text)'::regprocedure
     ) ilike '%is_farm_owner%'
     or pg_get_functiondef(
       'atlas.institutional_worker_day_shape_set_self_api_v1(uuid,uuid,smallint[],time without time zone,time without time zone,date,text)'::regprocedure
     ) ilike '%organization_memberships%'
  then
    raise exception 'Institutional Worker Day Shape v1 retains legacy authority semantics.';
  end if;
end
$validation$;
