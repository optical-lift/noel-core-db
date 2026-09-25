create table ledger.entity_contexts (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  entity_id uuid not null references reality.entities(id) on delete restrict,
  context_kind text not null check (btrim(context_kind)<>''),
  context_state text not null default 'active'
    check (context_state in ('active','paused','ended')),
  context_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(context_basis)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(ledger_id,entity_id,context_kind),
  check ((context_state='ended' and ended_at is not null) or (context_state<>'ended' and ended_at is null))
);

create index ledger_entity_contexts_ledger_state_idx
  on ledger.entity_contexts(ledger_id,context_kind,context_state,updated_at desc);
create index ledger_entity_contexts_entity_idx
  on ledger.entity_contexts(entity_id,context_state,ledger_id);

alter table ledger.entity_contexts enable row level security;
revoke all on table ledger.entity_contexts from public,anon,authenticated;
grant select,insert,update,delete on table ledger.entity_contexts to service_role;

alter table ledger.actions
  add column object_entity_id uuid null references reality.entities(id) on delete restrict;

create index ledger_actions_object_entity_idx
  on ledger.actions(ledger_id,object_entity_id,occurred_at desc)
  where object_entity_id is not null;

create or replace function ledger.guard_entity_context_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_ledger_state text;
  v_entity_state text;
begin
  select ledger_state into v_ledger_state
  from ledger.ledgers
  where id=new.ledger_id;

  if v_ledger_state is null or v_ledger_state<>'active' then
    raise exception 'Active Ledger required for Entity context.' using errcode='23514';
  end if;

  select identity_state into v_entity_state
  from reality.entities
  where id=new.entity_id;

  if v_entity_state is null or v_entity_state<>'canonical' then
    raise exception 'Canonical Reality Entity required for Ledger context.' using errcode='23514';
  end if;

  if new.context_state='ended' then
    new.ended_at:=coalesce(new.ended_at,now());
  else
    new.ended_at:=null;
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger ledger_entity_context_guard_v1
before insert or update on ledger.entity_contexts
for each row execute function ledger.guard_entity_context_v1();

create or replace function atlas.admit_shared_intelligence_entity_to_reality_service_v1(
  p_shared_entity_id uuid,
  p_admission_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_source local_intel.entities%rowtype;
  v_existing reality.entities%rowtype;
  v_collision uuid;
  v_inserted boolean:=false;
  v_route_count integer:=0;
begin
  if p_shared_entity_id is null then
    raise exception 'Shared Intelligence Entity id is required.' using errcode='22023';
  end if;

  if p_admission_basis is null or jsonb_typeof(p_admission_basis)<>'object' then
    raise exception 'Admission basis must be a JSON object.' using errcode='22023';
  end if;

  select * into v_source
  from local_intel.entities
  where id=p_shared_entity_id;

  if v_source.id is null then
    raise exception 'Shared Intelligence Entity not found.' using errcode='P0002';
  end if;

  if v_source.status is distinct from 'active' then
    raise exception 'Only an active Shared Intelligence Entity may be admitted to Reality.'
      using errcode='23514';
  end if;

  if nullif(btrim(v_source.stable_key),'') is null
     or nullif(btrim(v_source.entity_type),'') is null
     or nullif(btrim(v_source.name),'') is null then
    raise exception 'Shared Intelligence Entity is missing canonical identity fields.'
      using errcode='23514';
  end if;

  select * into v_existing
  from reality.entities
  where id=p_shared_entity_id;

  if v_existing.id is null then
    select e.id into v_collision
    from reality.entities e
    where e.stable_key=v_source.stable_key
      and e.id<>p_shared_entity_id
    limit 1;

    if v_collision is not null then
      raise exception 'Reality stable-key collision requires identity adjudication before admission.'
        using errcode='23505';
    end if;

    insert into reality.entities(
      id,stable_key,entity_kind,display_name,identity_state,metadata
    ) values (
      v_source.id,
      v_source.stable_key,
      v_source.entity_type,
      v_source.name,
      'canonical',
      jsonb_build_object(
        'admittedFrom','shared_intelligence',
        'sharedIntelligenceVerificationState',v_source.verification_state,
        'admissionBasis',p_admission_basis
      )
    );

    v_inserted:=true;
  elsif v_existing.identity_state<>'canonical' then
    raise exception 'Existing Reality Entity is not canonical; adjudication required.'
      using errcode='23514';
  end if;

  insert into reality.contact_routes(
    entity_id,route_kind,route_value,normalized_value,
    route_state,public_disclosure,evidence,metadata,
    first_observed_at,last_verified_at
  )
  select
    cp.entity_id,
    cp.contact_type,
    cp.contact_value,
    cp.normalized_value,
    case
      when cp.marketing_status='suppressed'
        or cp.deliverability_state='hard_bounce'
        or cp.suppression_reason is not null
      then 'suppressed'
      else 'observed'
    end,
    cp.visibility='public',
    jsonb_build_object(
      'sourceSystem','shared_intelligence',
      'sourceContactPointId',cp.id,
      'sourceId',cp.source_id,
      'verificationState',cp.verification_state,
      'deliverabilityState',cp.deliverability_state,
      'marketingStatus',cp.marketing_status,
      'visibility',cp.visibility
    ),
    jsonb_build_object(
      'sharedIntelligenceContext',cp.context,
      'contactScope',cp.contact_scope
    ),
    cp.created_at,
    cp.verified_at
  from local_intel.contact_points cp
  where cp.entity_id=p_shared_entity_id
    and nullif(btrim(cp.contact_type),'') is not null
    and nullif(btrim(cp.contact_value),'') is not null
    and nullif(btrim(cp.normalized_value),'') is not null
  on conflict(entity_id,route_kind,normalized_value)
  do update set
    route_value=excluded.route_value,
    public_disclosure=excluded.public_disclosure,
    evidence=reality.contact_routes.evidence || excluded.evidence,
    metadata=reality.contact_routes.metadata || excluded.metadata,
    last_verified_at=greatest(reality.contact_routes.last_verified_at,excluded.last_verified_at),
    updated_at=now(),
    route_state=case
      when reality.contact_routes.route_state in ('suppressed','retired')
        then reality.contact_routes.route_state
      else excluded.route_state
    end;

  select count(*)::integer into v_route_count
  from reality.contact_routes
  where entity_id=p_shared_entity_id
    and route_state<>'retired';

  select * into v_existing
  from reality.entities
  where id=p_shared_entity_id;

  return jsonb_build_object(
    'contractVersion','shared_intelligence_reality_admission_v1',
    'entityId',v_existing.id,
    'stableKey',v_existing.stable_key,
    'entityKind',v_existing.entity_kind,
    'displayName',v_existing.display_name,
    'identityState',v_existing.identity_state,
    'inserted',v_inserted,
    'reusedExistingRealityEntity',not v_inserted,
    'contactRouteCount',v_route_count,
    'identityRule','preserve_shared_intelligence_uuid_no_duplicate_referent'
  );
end
$function$;

revoke all on function atlas.admit_shared_intelligence_entity_to_reality_service_v1(uuid,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.admit_shared_intelligence_entity_to_reality_service_v1(uuid,jsonb)
  to service_role;

create or replace function ledger.upsert_entity_context_service_v1(
  p_ledger_id uuid,
  p_entity_id uuid,
  p_context_kind text,
  p_context_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row ledger.entity_contexts%rowtype;
begin
  if nullif(btrim(p_context_kind),'') is null then
    raise exception 'Entity context kind is required.' using errcode='22023';
  end if;

  if p_context_basis is null or jsonb_typeof(p_context_basis)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Context basis and metadata must be JSON objects.' using errcode='22023';
  end if;

  insert into ledger.entity_contexts(
    ledger_id,entity_id,context_kind,context_state,context_basis,metadata
  ) values (
    p_ledger_id,p_entity_id,btrim(p_context_kind),'active',p_context_basis,p_metadata
  )
  on conflict(ledger_id,entity_id,context_kind)
  do update set
    context_state='active',
    context_basis=ledger.entity_contexts.context_basis || excluded.context_basis,
    metadata=ledger.entity_contexts.metadata || excluded.metadata,
    ended_at=null,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','ledger_entity_context_v1',
    'contextId',v_row.id,
    'ledgerId',v_row.ledger_id,
    'entityId',v_row.entity_id,
    'contextKind',v_row.context_kind,
    'contextState',v_row.context_state
  );
end
$function$;

revoke all on function ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb)
  to service_role;

create or replace function ledger.record_entity_action_service_v1(
  p_ledger_id uuid,
  p_entity_id uuid,
  p_action_kind text,
  p_performed_by_entity_id uuid default null,
  p_occurred_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_action ledger.actions%rowtype;
  v_ledger_state text;
  v_entity_state text;
begin
  if nullif(btrim(p_action_kind),'') is null then
    raise exception 'Action kind is required.' using errcode='22023';
  end if;

  if p_occurred_at is null then
    raise exception 'Action occurred_at is required.' using errcode='22023';
  end if;

  if p_payload is null or jsonb_typeof(p_payload)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Action payload and provenance must be JSON objects.' using errcode='22023';
  end if;

  select ledger_state into v_ledger_state
  from ledger.ledgers
  where id=p_ledger_id;

  if v_ledger_state is null or v_ledger_state<>'active' then
    raise exception 'Active Ledger required for Entity action.' using errcode='23514';
  end if;

  select identity_state into v_entity_state
  from reality.entities
  where id=p_entity_id;

  if v_entity_state is null or v_entity_state<>'canonical' then
    raise exception 'Canonical Reality Entity required for Entity action.' using errcode='23514';
  end if;

  if not exists (
    select 1
    from ledger.entity_contexts c
    where c.ledger_id=p_ledger_id
      and c.entity_id=p_entity_id
      and c.context_state='active'
  ) then
    raise exception 'Entity must have an active Ledger context before actions may be recorded.'
      using errcode='23514';
  end if;

  if p_performed_by_entity_id is not null then
    perform reality.assert_person_entity_v1(p_performed_by_entity_id);
  end if;

  insert into ledger.actions(
    ledger_id,action_kind,performed_by_entity_id,object_entity_id,
    occurred_at,payload,provenance,idempotency_key
  ) values (
    p_ledger_id,btrim(p_action_kind),p_performed_by_entity_id,p_entity_id,
    p_occurred_at,p_payload,p_provenance,nullif(btrim(p_idempotency_key),'')
  )
  on conflict(ledger_id,idempotency_key) do nothing
  returning * into v_action;

  if v_action.id is null then
    select * into v_action
    from ledger.actions
    where ledger_id=p_ledger_id
      and idempotency_key=nullif(btrim(p_idempotency_key),'')
    order by created_at desc,id
    limit 1;

    if v_action.id is null
       or v_action.object_entity_id is distinct from p_entity_id
       or v_action.action_kind<>btrim(p_action_kind) then
      raise exception 'Ledger action idempotency key collides with a different action.'
        using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_entity_action_v1',
    'actionId',v_action.id,
    'ledgerId',v_action.ledger_id,
    'entityId',v_action.object_entity_id,
    'actionKind',v_action.action_kind,
    'occurredAt',v_action.occurred_at,
    'performedByEntityId',v_action.performed_by_entity_id
  );
end
$function$;

revoke all on function ledger.record_entity_action_service_v1(
  uuid,uuid,text,uuid,timestamptz,jsonb,jsonb,text
) from public,anon,authenticated;
grant execute on function ledger.record_entity_action_service_v1(
  uuid,uuid,text,uuid,timestamptz,jsonb,jsonb,text
) to service_role;

create or replace function atlas.attach_shared_intelligence_entity_to_ledger_service_v1(
  p_ledger_id uuid,
  p_shared_entity_id uuid,
  p_context_kind text,
  p_context_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_performed_by_entity_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_admission jsonb;
  v_context jsonb;
  v_action jsonb;
begin
  v_admission:=atlas.admit_shared_intelligence_entity_to_reality_service_v1(
    p_shared_entity_id,p_context_basis
  );

  v_context:=ledger.upsert_entity_context_service_v1(
    p_ledger_id,p_shared_entity_id,p_context_kind,p_context_basis,p_metadata
  );

  v_action:=ledger.record_entity_action_service_v1(
    p_ledger_id,
    p_shared_entity_id,
    'entity_context_established',
    p_performed_by_entity_id,
    now(),
    jsonb_build_object(
      'contextId',v_context->>'contextId',
      'contextKind',p_context_kind
    ),
    jsonb_build_object(
      'source','shared_intelligence_reality_ledger_bridge',
      'admission',v_admission
    ),
    'entity-context:'||p_shared_entity_id::text||':'||btrim(p_context_kind)
  );

  return jsonb_build_object(
    'contractVersion','shared_intelligence_ledger_attachment_v1',
    'admission',v_admission,
    'context',v_context,
    'action',v_action
  );
end
$function$;

revoke all on function atlas.attach_shared_intelligence_entity_to_ledger_service_v1(
  uuid,uuid,text,jsonb,jsonb,uuid
) from public,anon,authenticated;
grant execute on function atlas.attach_shared_intelligence_entity_to_ledger_service_v1(
  uuid,uuid,text,jsonb,jsonb,uuid
) to service_role;

create or replace function atlas.require_ledger_external_entity_responsibility_v1(
  p_ledger_id uuid,
  p_operation_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_subject_entity_id uuid;
  v_ledger_state text;
  v_relation_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  select l.subject_entity_id,l.ledger_state
  into v_subject_entity_id,v_ledger_state
  from ledger.ledgers l
  where l.id=p_ledger_id;

  if v_subject_entity_id is null or v_ledger_state<>'active' then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  v_relation_id:=reality.resolve_responsibility_relation_v1(
    v_person_id,
    'institutional_external_entity_engagement',
    p_operation_key,
    'entity',
    v_subject_entity_id,
    null,
    jsonb_build_object('ledgerIds',jsonb_build_array(p_ledger_id::text))
  );

  if v_relation_id is null then
    raise exception 'Institutional external-Entity responsibility required.'
      using errcode='42501';
  end if;

  return v_relation_id;
end
$function$;

revoke all on function atlas.require_ledger_external_entity_responsibility_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function atlas.require_ledger_external_entity_responsibility_v1(uuid,text)
  to service_role;

create or replace function atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
  p_ledger_id uuid,
  p_shared_entity_id uuid,
  p_context_kind text,
  p_context_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
  v_result jsonb;
begin
  v_person_id:=atlas.current_person_id_v1();

  v_relation_id:=atlas.require_ledger_external_entity_responsibility_v1(
    p_ledger_id,'ledger_entity_attach'
  );

  v_result:=atlas.attach_shared_intelligence_entity_to_ledger_service_v1(
    p_ledger_id,
    p_shared_entity_id,
    p_context_kind,
    p_context_basis,
    p_metadata || jsonb_build_object('responsibilityRelationId',v_relation_id),
    v_person_id
  );

  return v_result || jsonb_build_object(
    'authority',jsonb_build_object(
      'responsibilityRelationId',v_relation_id,
      'carrierPersonEntityId',v_person_id
    )
  );
end
$function$;

revoke all on function atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
  uuid,uuid,text,jsonb,jsonb
) from public,anon;
grant execute on function atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
  uuid,uuid,text,jsonb,jsonb
) to authenticated;

create or replace function atlas.record_ledger_entity_action_self_api_v1(
  p_ledger_id uuid,
  p_entity_id uuid,
  p_action_kind text,
  p_occurred_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_relation_id uuid;
begin
  v_person_id:=atlas.current_person_id_v1();

  v_relation_id:=atlas.require_ledger_external_entity_responsibility_v1(
    p_ledger_id,'ledger_entity_action'
  );

  return ledger.record_entity_action_service_v1(
    p_ledger_id,
    p_entity_id,
    p_action_kind,
    v_person_id,
    p_occurred_at,
    p_payload,
    p_provenance || jsonb_build_object(
      'authoritySource','reality_responsibility_relation',
      'responsibilityRelationId',v_relation_id
    ),
    p_idempotency_key
  );
end
$function$;

revoke all on function atlas.record_ledger_entity_action_self_api_v1(
  uuid,uuid,text,timestamptz,jsonb,jsonb,text
) from public,anon;
grant execute on function atlas.record_ledger_entity_action_self_api_v1(
  uuid,uuid,text,timestamptz,jsonb,jsonb,text
) to authenticated;

create or replace function atlas.ledger_entity_contexts_self_api_v1(
  p_ledger_id uuid,
  p_context_kind text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_person_id uuid;
  v_items jsonb;
begin
  v_person_id:=atlas.current_person_id_v1();

  if not exists (
    select 1
    from ledger.seats s
    join ledger.ledgers l
      on l.id=s.ledger_id
     and l.ledger_state='active'
    where s.ledger_id=p_ledger_id
      and s.person_entity_id=v_person_id
      and s.seat_state='active'
  ) then
    raise exception 'Active Ledger Seat required for Entity-context read.'
      using errcode='42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'contextId',c.id,
      'contextKind',c.context_kind,
      'contextState',c.context_state,
      'entity',jsonb_build_object(
        'id',e.id,
        'stableKey',e.stable_key,
        'entityKind',e.entity_kind,
        'displayName',e.display_name,
        'identityState',e.identity_state
      ),
      'contactRoutes',coalesce(routes.items,'[]'::jsonb),
      'lastAction',case
        when last_action.id is null then null
        else jsonb_build_object(
          'actionId',last_action.id,
          'actionKind',last_action.action_kind,
          'occurredAt',last_action.occurred_at,
          'performedByEntityId',last_action.performed_by_entity_id,
          'payload',last_action.payload
        )
      end,
      'basis',c.context_basis,
      'metadata',c.metadata,
      'updatedAt',c.updated_at
    )
    order by c.updated_at desc,c.id
  ),'[]'::jsonb)
  into v_items
  from ledger.entity_contexts c
  join reality.entities e
    on e.id=c.entity_id
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'routeKind',r.route_kind,
        'routeValue',r.route_value,
        'routeState',r.route_state,
        'lastVerifiedAt',r.last_verified_at
      )
      order by r.route_kind,r.route_value
    ) as items
    from reality.contact_routes r
    where r.entity_id=c.entity_id
      and r.route_state not in ('retired','suppressed')
      and r.public_disclosure
  ) routes on true
  left join lateral (
    select a.id,a.action_kind,a.occurred_at,a.performed_by_entity_id,a.payload
    from ledger.actions a
    where a.ledger_id=c.ledger_id
      and a.object_entity_id=c.entity_id
    order by a.occurred_at desc,a.id desc
    limit 1
  ) last_action on true
  where c.ledger_id=p_ledger_id
    and (p_context_kind is null or c.context_kind=p_context_kind);

  return jsonb_build_object(
    'contractVersion','ledger_entity_contexts_self_v1',
    'ledgerId',p_ledger_id,
    'items',v_items,
    'identityRoot','reality.entities',
    'contextSemantics','ledger_private_not_canonical_relationship'
  );
end
$function$;

revoke all on function atlas.ledger_entity_contexts_self_api_v1(uuid,text)
  from public,anon;
grant execute on function atlas.ledger_entity_contexts_self_api_v1(uuid,text)
  to authenticated;

do $block$
declare
  v_lex uuid;
  v_elm uuid;
  v_venue_ledger uuid;
begin
  select id into v_lex
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  select id into v_elm
  from reality.entities
  where stable_key='elm-farm'
    and identity_state='canonical';

  select id into v_venue_ledger
  from ledger.ledgers
  where stable_key='elm-farm:venue'
    and ledger_state='active';

  if v_lex is null or v_elm is null or v_venue_ledger is null then
    raise exception 'Lex + Elm Venue Reality/Ledger cutover must exist before external-Entity bridge.'
      using errcode='23514';
  end if;

  if not exists (
    select 1
    from reality.responsibility_relations rr
    where rr.carrier_person_entity_id=v_lex
      and rr.responsibility_key='institutional_external_entity_engagement'
      and rr.jurisdiction_kind='entity'
      and rr.jurisdiction_entity_id=v_elm
      and rr.relation_state='active'
  ) then
    insert into reality.responsibility_relations(
      carrier_person_entity_id,responsibility_key,title,relation_state,
      jurisdiction_kind,jurisdiction_entity_id,permitted_operations,scope,
      establishment_kind,source_person_entity_id,establishment_basis
    ) values (
      v_lex,
      'institutional_external_entity_engagement',
      'Elm external entity engagement',
      'active',
      'entity',
      v_elm,
      array['ledger_entity_attach','ledger_entity_action']::text[],
      jsonb_build_object(
        'ledgerIds',jsonb_build_array(v_venue_ledger::text),
        'purpose','venue_external_entity_engagement'
      ),
      'reality_ledger_cutover',
      v_lex,
      jsonb_build_object(
        'basis','Elm Venue requires bounded authority to select external Entities and record engagement actions without reviving Organization-role authority.',
        'establishedByMigration','atlas_reality_ledger_external_entity_bridge_v1'
      )
    );
  end if;
end
$block$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid, uuid, text, jsonb, jsonb)',
  'app_endpoint','verified','active',
  true,true,false,0,1,
  jsonb_build_object(
    'purpose','Admit/reuse one canonical Shared Intelligence Entity and establish a Ledger-private context around it.',
    'identityRoot','reality.entities',
    'authority','reality.responsibility_relations',
    'forbiddenAuthoritySources',jsonb_build_array(
      'atlas.organization_memberships',
      'atlas.principal_ledger_authorities'
    )
  ),
  now(),false
),
(
  'atlas.record_ledger_entity_action_self_api_v1(uuid, uuid, text, timestamp with time zone, jsonb, jsonb, text)',
  'app_endpoint','verified','active',
  true,true,false,0,1,
  jsonb_build_object(
    'purpose','Append an action by an institution around an already-linked canonical Reality Entity.',
    'authority','reality.responsibility_relations',
    'targetIdentity','ledger.actions.object_entity_id -> reality.entities.id'
  ),
  now(),false
),
(
  'atlas.ledger_entity_contexts_self_api_v1(uuid, text)',
  'app_endpoint','verified','active',
  true,true,false,0,1,
  jsonb_build_object(
    'purpose','Read the signed-in Person''s active Ledger-private Entity contexts through Ledger Seat participation.',
    'readAuthority','ledger.seats',
    'identityRoot','reality.entities'
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

comment on table ledger.entity_contexts is
  'Ledger-private context around a canonical Reality Entity. A context does not create identity, establish a real-world relationship, grant authority, or grant Ledger access.';

comment on column ledger.actions.object_entity_id is
  'Optional canonical Reality Entity that is the object/counterparty of the Ledger action. Identity remains rooted in reality.entities.';

comment on function atlas.admit_shared_intelligence_entity_to_reality_service_v1(uuid,jsonb) is
  'Atlas adapter from resolved Shared Intelligence identity into Reality. Preserves the Shared Intelligence UUID and refuses stable-key collisions rather than minting a duplicate.';

comment on function ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb) is
  'Generic Ledger service for establishing a private context around an already-canonical Reality Entity. It has no Shared Intelligence dependency.';

comment on function ledger.record_entity_action_service_v1(uuid,uuid,text,uuid,timestamptz,jsonb,jsonb,text) is
  'Generic Ledger service for appending an Entity-targeted action. The target must already have an active Ledger context.';

comment on function atlas.attach_shared_intelligence_entity_to_ledger_service_v1(uuid,uuid,text,jsonb,jsonb,uuid) is
  'Atlas boundary adapter composing Shared Intelligence admission, generic Ledger Entity context, and first Ledger action.';

comment on function atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb) is
  'Authenticated bridge through exact Reality responsibility. Does not use legacy Organization Membership or Principal Ledger Authority.';

comment on function atlas.record_ledger_entity_action_self_api_v1(uuid,uuid,text,timestamptz,jsonb,jsonb,text) is
  'Authenticated write path for actions around a canonical Entity already active in the Ledger context.';

comment on function atlas.ledger_entity_contexts_self_api_v1(uuid,text) is
  'Seat-gated read projection of Ledger-private Entity contexts and their latest action; no Organization overlay is consulted.';

do $validation$
begin
  if to_regclass('ledger.entity_contexts') is null then
    raise exception 'Ledger Entity context table missing.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='ledger'
      and table_name='actions'
      and column_name='object_entity_id'
  ) then
    raise exception 'Ledger actions canonical Entity object column missing.';
  end if;

  if pg_get_functiondef(
       'ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%local_intel%' then
    raise exception 'Ledger core Entity-context service depends directly on Shared Intelligence.';
  end if;

  if pg_get_functiondef(
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%principal_ledger_authorities%' then
    raise exception 'External Entity bridge depends on retired authority structures.';
  end if;
end
$validation$;
