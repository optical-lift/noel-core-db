begin;

create table if not exists atlas.implementation_case_sources (
  id uuid primary key default gen_random_uuid(),
  implementation_case_id uuid not null references atlas.implementation_cases(id) on delete cascade,
  provider_key text not null,
  display_label text not null,
  source_state text not null default 'identified' check (source_state in ('identified','authorization_pending','connected','blocked','removed')),
  requirement_state text not null default 'unclassified' check (requirement_state in ('unclassified','required','deferred','not_required')),
  connected_source_id uuid null references atlas.connected_sources(id) on delete set null,
  identified_by_user_id uuid not null references auth.users(id),
  authorized_by_user_id uuid null references auth.users(id),
  blocker text null,
  usable_at timestamptz null,
  authorization_context jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz null,
  constraint implementation_case_sources_provider_key_nonempty check (btrim(provider_key) <> ''),
  constraint implementation_case_sources_display_label_nonempty check (btrim(display_label) <> ''),
  constraint implementation_case_sources_connected_consistency check (
    (source_state = 'connected' and connected_source_id is not null and usable_at is not null)
    or source_state <> 'connected'
  )
);

create index if not exists implementation_case_sources_case_idx
  on atlas.implementation_case_sources (implementation_case_id, created_at, id);
create index if not exists implementation_case_sources_connected_source_idx
  on atlas.implementation_case_sources (connected_source_id)
  where connected_source_id is not null;

comment on table atlas.implementation_case_sources is
  'Implementation-scoped source inventory and connection readiness. A row is evidence about a source relevant to an implementation case; it does not establish Organization, Ledger scope, membership, authority, or canonical source ownership.';
comment on column atlas.implementation_case_sources.requirement_state is
  'Implementation requirement classification. Setup sponsors may identify sources; practitioner governance determines required/deferred/not_required.';
comment on column atlas.implementation_case_sources.connected_source_id is
  'Optional link to a technically usable connected source after provider authorization. It does not bind the source to an Organization or Ledger.';

revoke all on atlas.implementation_case_sources from anon, authenticated;

create or replace function atlas.implementation_home_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  with cases as (
    select
      c.id,
      c.state,
      c.opened_at,
      p.starting_label,
      p.purchased_at,
      (
        select count(*)::int
        from atlas.ledger_entitlements le
        where le.implementation_case_id = c.id
          and le.state <> 'retired'
      ) as purchased_ledger_entitlement_count,
      exists (
        select 1
        from atlas.implementation_case_participants practitioner
        where practitioner.implementation_case_id = c.id
          and practitioner.relationship_kind = 'practitioner'
          and practitioner.active
      ) as has_practitioner
    from atlas.implementation_cases c
    join atlas.implementation_purchases p on p.id = c.implementation_purchase_id
    join atlas.implementation_case_participants sponsor
      on sponsor.implementation_case_id = c.id
     and sponsor.relationship_kind = 'setup_sponsor'
     and sponsor.active
     and sponsor.human_user_id = auth.uid()
    where auth.uid() is not null
      and c.state not in ('closed','cancelled')
      and p.purchase_state = 'active'
  )
  select jsonb_build_object(
    'ok', true,
    'contractVersion', 'implementation_home_self_api_v1',
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'implementationCaseId', c.id,
        'caseState', c.state,
        'startingLabel', c.starting_label,
        'purchasedAt', c.purchased_at,
        'purchasedLedgerEntitlementCount', c.purchased_ledger_entitlement_count,
        'hasPractitioner', c.has_practitioner,
        'sources', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', s.id,
            'providerKey', s.provider_key,
            'displayLabel', s.display_label,
            'sourceState', s.source_state,
            'requirementState', s.requirement_state,
            'connectedSourceId', s.connected_source_id,
            'blocker', s.blocker,
            'usableAt', s.usable_at,
            'createdAt', s.created_at,
            'updatedAt', s.updated_at
          ) order by s.created_at, s.id)
          from atlas.implementation_case_sources s
          where s.implementation_case_id = c.id
            and s.source_state <> 'removed'
        ), '[]'::jsonb)
      ) order by c.purchased_at desc, c.id)
      from cases c
    ), '[]'::jsonb)
  );
$function$;

create or replace function atlas.identify_implementation_source_self_api_v1(
  p_implementation_case_id uuid,
  p_provider_key text,
  p_display_label text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_provider_key text := lower(btrim(coalesce(p_provider_key,'')));
  v_display_label text := btrim(coalesce(p_display_label,''));
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Atlas authentication required.' using errcode='42501';
  end if;
  if v_provider_key = '' or v_provider_key !~ '^[a-z0-9][a-z0-9_:-]{0,79}$' then
    raise exception 'Valid provider key required.' using errcode='22023';
  end if;
  if v_display_label = '' or char_length(v_display_label) > 160 then
    raise exception 'Source label required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Metadata must be a JSON object.' using errcode='22023';
  end if;
  if not exists (
    select 1
    from atlas.implementation_case_participants sponsor
    join atlas.implementation_cases c on c.id = sponsor.implementation_case_id
    where sponsor.implementation_case_id = p_implementation_case_id
      and sponsor.relationship_kind = 'setup_sponsor'
      and sponsor.active
      and sponsor.human_user_id = auth.uid()
      and c.state not in ('closed','cancelled')
  ) then
    raise exception 'Active setup-sponsor relationship required.' using errcode='42501';
  end if;

  select s.id into v_id
  from atlas.implementation_case_sources s
  where s.implementation_case_id = p_implementation_case_id
    and s.source_state <> 'removed'
    and s.provider_key = v_provider_key
    and lower(s.display_label) = lower(v_display_label)
  order by s.created_at
  limit 1;

  if v_id is null then
    insert into atlas.implementation_case_sources (
      implementation_case_id,
      provider_key,
      display_label,
      source_state,
      requirement_state,
      identified_by_user_id,
      metadata
    ) values (
      p_implementation_case_id,
      v_provider_key,
      v_display_label,
      'identified',
      'unclassified',
      auth.uid(),
      jsonb_build_object('source','atlas_implementation_home') || p_metadata
    ) returning id into v_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'implementationCaseSourceId', v_id,
    'implementationCaseId', p_implementation_case_id,
    'providerKey', v_provider_key,
    'displayLabel', v_display_label,
    'canonicalOrganizationCreated', false,
    'ledgerBindingCreated', false,
    'membershipCreated', false
  );
end;
$function$;

create or replace function atlas.remove_implementation_source_self_api_v1(
  p_implementation_case_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_case_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Atlas authentication required.' using errcode='42501';
  end if;

  select s.implementation_case_id into v_case_id
  from atlas.implementation_case_sources s
  where s.id = p_implementation_case_source_id
    and s.source_state <> 'removed';

  if v_case_id is null or not exists (
    select 1
    from atlas.implementation_case_participants sponsor
    where sponsor.implementation_case_id = v_case_id
      and sponsor.relationship_kind = 'setup_sponsor'
      and sponsor.active
      and sponsor.human_user_id = auth.uid()
  ) then
    raise exception 'Active setup-sponsor relationship required.' using errcode='42501';
  end if;

  update atlas.implementation_case_sources
  set source_state='removed', removed_at=now(), updated_at=now()
  where id=p_implementation_case_source_id;

  return jsonb_build_object('ok',true,'implementationCaseSourceId',p_implementation_case_source_id);
end;
$function$;

create or replace function atlas.implementation_case_workspace_self_api_v1(p_implementation_case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_result jsonb;
begin
  if not atlas.implementation_practitioner_authorized_self_v1() then
    return jsonb_build_object('ok',false,'code','practitioner_authority_required');
  end if;

  if not exists (select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id) then
    return jsonb_build_object('ok',false,'code','case_not_found');
  end if;

  select jsonb_build_object(
    'ok',true,
    'contractVersion','implementation_case_workspace_self_api_v1',
    'sources',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,
        'providerKey',s.provider_key,
        'displayLabel',s.display_label,
        'sourceState',s.source_state,
        'requirementState',s.requirement_state,
        'connectedSourceId',s.connected_source_id,
        'blocker',s.blocker,
        'usableAt',s.usable_at,
        'identifiedByUserId',s.identified_by_user_id,
        'authorizedByUserId',s.authorized_by_user_id,
        'createdAt',s.created_at,
        'updatedAt',s.updated_at
      ) order by s.created_at,s.id)
      from atlas.implementation_case_sources s
      where s.implementation_case_id=p_implementation_case_id and s.source_state<>'removed'
    ),'[]'::jsonb),
    'establishmentItems',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'category',e.category,'title',e.title,'detail',e.detail,'status',e.status,
        'createdAt',e.created_at,'updatedAt',e.updated_at
      ) order by e.created_at,e.id)
      from atlas.implementation_establishment_items e
      where e.implementation_case_id=p_implementation_case_id and e.status<>'superseded'
    ),'[]'::jsonb),
    'threads',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',t.id,'workArea',t.work_area,'title',t.title,'state',t.state,'createdAt',t.created_at,
        'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'body',n.body,'createdAt',n.created_at) order by n.created_at,n.id) from atlas.implementation_notes n where n.implementation_thread_id=t.id),'[]'::jsonb),
        'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'kind',e.evidence_kind,'label',e.label,'detail',e.detail,'referenceUri',e.reference_uri,'createdAt',e.created_at) order by e.created_at,e.id) from atlas.implementation_evidence_refs e where e.implementation_thread_id=t.id),'[]'::jsonb),
        'findings',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'statement',f.statement,'status',f.status,'createdAt',f.created_at) order by f.created_at,f.id) from atlas.implementation_findings f where f.implementation_thread_id=t.id),'[]'::jsonb),
        'requests',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'requestText',r.request_text,'status',r.status,'createdAt',r.created_at) order by r.created_at,r.id) from atlas.implementation_requests r where r.implementation_thread_id=t.id),'[]'::jsonb)
      ) order by t.created_at,t.id)
      from atlas.implementation_threads t
      where t.implementation_case_id=p_implementation_case_id
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- The exposed public membrane carries only the narrow self-service contracts.
create or replace function public.implementation_home_self_api_v1()
returns jsonb
language sql
stable
security invoker
set search_path to 'pg_catalog','atlas','public'
as $function$
  select atlas.implementation_home_self_api_v1();
$function$;

create or replace function public.identify_implementation_source_self_api_v1(
  p_implementation_case_id uuid,
  p_provider_key text,
  p_display_label text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','atlas','public'
as $function$
  select atlas.identify_implementation_source_self_api_v1(
    p_implementation_case_id,
    p_provider_key,
    p_display_label,
    p_metadata
  );
$function$;

create or replace function public.remove_implementation_source_self_api_v1(
  p_implementation_case_source_id uuid
)
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog','atlas','public'
as $function$
  select atlas.remove_implementation_source_self_api_v1(p_implementation_case_source_id);
$function$;

revoke all on function atlas.implementation_home_self_api_v1() from public;
revoke all on function atlas.identify_implementation_source_self_api_v1(uuid,text,text,jsonb) from public;
revoke all on function atlas.remove_implementation_source_self_api_v1(uuid) from public;
revoke all on function public.implementation_home_self_api_v1() from public, anon;
revoke all on function public.identify_implementation_source_self_api_v1(uuid,text,text,jsonb) from public, anon;
revoke all on function public.remove_implementation_source_self_api_v1(uuid) from public, anon;

grant execute on function atlas.implementation_home_self_api_v1() to authenticated;
grant execute on function atlas.identify_implementation_source_self_api_v1(uuid,text,text,jsonb) to authenticated;
grant execute on function atlas.remove_implementation_source_self_api_v1(uuid) to authenticated;
grant execute on function public.implementation_home_self_api_v1() to authenticated;
grant execute on function public.identify_implementation_source_self_api_v1(uuid,text,text,jsonb) to authenticated;
grant execute on function public.remove_implementation_source_self_api_v1(uuid) to authenticated;

commit;
