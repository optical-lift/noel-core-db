-- REVIEW CANDIDATE, NOT AN EXECUTABLE MIGRATION OR PRODUCTION RELEASE.
-- Atlas-only post-fence machinery; first generate a numbered canonical
-- migration through the reviewed noel-core-db CLI workflow, THEN validate
-- that exact migration on a disposable production-schema clone.
-- Existing canonical relation graph: atlas.work_item_relations.
-- No new Work or duplicate dependency truth store.

-- All active depends_on writers (including older communication-derived Work)
-- must share the same cycle protection, not only the new RPC.
create or replace function atlas.guard_work_item_depends_on_cycle_v1()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_cycle boolean;
  v_deep boolean;
begin
  if new.relation_kind <> 'depends_on' or not new.active then
    return new;
  end if;
  if new.from_work_item_id=new.to_work_item_id then
    raise exception 'Work cannot depend on itself.' using errcode='23514';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(new.organization_id::text),
    pg_catalog.hashtext('atlas.work_item_relations.depends_on')
  );
  with recursive walk(id, path) as (
    select new.to_work_item_id, array[new.to_work_item_id]::uuid[]
    union all
    select r.to_work_item_id, walk.path || r.to_work_item_id
    from walk
    join atlas.work_item_relations r
      on r.organization_id=new.organization_id
     and r.from_work_item_id=walk.id
     and r.relation_kind='depends_on' and r.active
     and r.id is distinct from new.id
    where pg_catalog.cardinality(walk.path)<256
      and not (r.to_work_item_id=any(walk.path))
  )
  select coalesce(bool_or(id=new.from_work_item_id),false),
         coalesce(bool_or(pg_catalog.cardinality(path)>=256),false)
    into v_cycle,v_deep from walk;
  if v_cycle or v_deep then
    raise exception 'Prerequisite cycle or unprovably deep Work graph.'
      using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_work_item_depends_on_cycle_v1()
  from public, anon, authenticated;
drop trigger if exists guard_work_item_depends_on_cycle_v1
  on atlas.work_item_relations;
create trigger guard_work_item_depends_on_cycle_v1
before insert or update of organization_id,from_work_item_id,
  to_work_item_id,relation_kind,active
on atlas.work_item_relations
for each row execute function atlas.guard_work_item_depends_on_cycle_v1();

-- Historical evidence of operations only; atlas.work_item_relations stays
-- the ONE canonical relationship. Deliberately no FK that turns work
-- retirement into an unanticipated restricted/deleted operation.
create table if not exists atlas.work_item_prerequisite_events_v1(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  ledger_id uuid not null,
  relation_id uuid not null,
  downstream_work_item_id uuid not null,
  prerequisite_work_item_id uuid not null,
  actor_person_id uuid not null,
  source_action_id text not null,
  request_fingerprint text not null,
  action_kind text not null check(action_kind in ('establish','withdraw')),
  before_active boolean,
  after_active boolean not null,
  before_satisfied_at timestamptz,
  after_satisfied_at timestamptz,
  reason text not null check(length(btrim(reason))>=8),
  recorded_at timestamptz not null default now(),
  unique(actor_person_id,source_action_id)
);
create index if not exists work_item_prerequisite_events_v1_relation_idx
  on atlas.work_item_prerequisite_events_v1(organization_id,relation_id,recorded_at);
alter table atlas.work_item_prerequisite_events_v1 enable row level security;
revoke all on atlas.work_item_prerequisite_events_v1 from public,anon,authenticated;

-- Event custody is truly append-only, not merely an application convention.
-- This protects against accidental UPDATE/DELETE from future definer writers
-- as well as direct browser writes already denied by RLS and privileges.
create or replace function atlas.guard_work_item_prerequisite_event_immutable_v1()
returns trigger language plpgsql set search_path=''
as $$
begin
  raise exception 'Original prerequisite action history cannot be updated or deleted.'
    using errcode='23514';
end;
$$;
revoke all on function atlas.guard_work_item_prerequisite_event_immutable_v1()
  from public,anon,authenticated;
drop trigger if exists guard_work_item_prerequisite_event_immutable_v1
  on atlas.work_item_prerequisite_events_v1;
create trigger guard_work_item_prerequisite_event_immutable_v1
before update or delete on atlas.work_item_prerequisite_events_v1
for each row execute function atlas.guard_work_item_prerequisite_event_immutable_v1();

-- Reuse current, exact, evidenced Ledger relevance. Another organization
-- or a loose connection/seat never creates access to Work.
create or replace function atlas.work_prerequisite_ledger_scope_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(
    select 1 from atlas.work_items w
    join atlas.company_work_native_ledger_relevance r
      on r.organization_id=w.organization_id and r.work_item_id=w.id
    where w.id=p_work_item_id and w.organization_id=p_organization_id
      and r.ledger_id=p_ledger_id and r.attribution_state='active'
      and (
        r.evidence_kind in ('owner_attested','participant_attested')
        or (r.evidence_kind='source_verified' and exists(
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            r.work_item_id,r.ledger_id) s
          where s.source_schema=r.source_schema
            and s.source_table=r.source_table and s.source_id=r.source_id
        ))
      )
  );
$$;
revoke all on function atlas.work_prerequisite_ledger_scope_v1(uuid,uuid,uuid)
  from public,anon,authenticated;

create or replace function atlas.work_prerequisite_candidates_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,
  p_limit integer default 50,p_after_work_item_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
  v_actor uuid;
  v_items jsonb;
begin
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'Limit must be 1..100.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'title',w.title,'workState',w.work_state,
    'ledgerId',p_ledger_id,'organizationId',w.organization_id
  ) order by w.id),'[]'::jsonb)
  into v_items
  from (
    select t.* from atlas.work_items t
    where t.organization_id=p_organization_id
      and t.work_state in ('open','completed')
      and (p_after_work_item_id is null or t.id>p_after_work_item_id)
      and atlas.work_prerequisite_ledger_scope_v1(
        p_organization_id,p_ledger_id,t.id)
    order by t.id limit p_limit
  ) w;
  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_work_prerequisite_candidates_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'scope','exact_governing_principal_and_current_ledger_evidence',
    'items',v_items,'nextAfterWorkItemId',
    case when jsonb_array_length(v_items)=p_limit then v_items->(p_limit-1)->>'id'
         else null end,
    'notAllLedgers',true,'notAllDates',false,
    'candidateIsNotEstablishedRelation',true
  );
end;
$$;

create or replace function atlas.work_prerequisites_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_downstream_work_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
  v_actor uuid;
  v_records jsonb;
begin
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if not atlas.work_prerequisite_ledger_scope_v1(
    p_organization_id,p_ledger_id,p_downstream_work_item_id) then
    raise exception 'Downstream Work lacks current Ledger evidence.' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'relationId',r.id,'downstreamWorkItemId',r.from_work_item_id,
    'prerequisiteWorkItemId',r.to_work_item_id,
    'title',pre.title,'prerequisiteWorkState',pre.work_state,
    'relationKind',r.relation_kind,'active',r.active,
    'recordedSatisfiedAt',r.satisfied_at,
    'satisfactionNotInferredFromText',true
  ) order by r.id),'[]'::jsonb)
  into v_records
  from atlas.work_item_relations r
  join atlas.work_items pre on pre.id=r.to_work_item_id
  where r.organization_id=p_organization_id
    and r.from_work_item_id=p_downstream_work_item_id
    and r.relation_kind='depends_on'
    and atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,r.to_work_item_id);
  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_work_prerequisites_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'downstreamWorkItemId',p_downstream_work_item_id,
    'relations',v_records,'onlyCurrentLedgerEvidence',true
  );
end;
$$;

create or replace function atlas.set_work_prerequisite_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,
  p_downstream_work_item_id uuid,p_prerequisite_work_item_id uuid,
  p_enabled boolean,p_reason text,p_source_action_id text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_actor uuid;
  v_prior atlas.work_item_prerequisite_events_v1%rowtype;
  v_link atlas.work_item_relations%rowtype;
  v_downstream atlas.work_items%rowtype;
  v_prerequisite atlas.work_items%rowtype;
  v_fingerprint text;
  v_before boolean;
  v_before_satisfied_at timestamptz;
  v_applied boolean:=false;
  v_event_id uuid;
begin
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  if p_downstream_work_item_id is null or p_prerequisite_work_item_id is null
     or p_downstream_work_item_id=p_prerequisite_work_item_id
     or p_enabled is null or length(btrim(coalesce(p_reason,'')))<8
     or length(coalesce(p_source_action_id,''))<8
     or length(p_source_action_id)>128 then
    raise exception 'Original Work, intended state, reason and source action required.'
      using errcode='22023';
  end if;
  v_fingerprint:=md5(concat_ws('|',p_organization_id::text,p_ledger_id::text,
    p_downstream_work_item_id::text,p_prerequisite_work_item_id::text,
    p_enabled::text,p_reason));

  -- Serializes sibling edits and prevents concurrent A->B/B->A cycles.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_organization_id::text),
    pg_catalog.hashtext('atlas.work_item_relations.depends_on'));

  select * into v_prior from atlas.work_item_prerequisite_events_v1
    where actor_person_id=v_actor and source_action_id=p_source_action_id;
  if found then
    if v_prior.request_fingerprint<>v_fingerprint then
      raise exception 'Source action ID was already used for different work.'
        using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'contractVersion','atlas_work_prerequisite_set_v1',
      'relationId',v_prior.relation_id,'organizationId',p_organization_id,
      'ledgerId',p_ledger_id,
      'downstreamWorkItemId',v_prior.downstream_work_item_id,
      'prerequisiteWorkItemId',v_prior.prerequisite_work_item_id,
      'active',v_prior.after_active,'applied',false,'idempotentReplay',true,
      'recordedEventId',v_prior.id,
      'doesNotCreateWork',true,'doesNotAutomaticallyBlockWork',true);
  end if;

  -- Stable row-lock ordering prevents deadlocks in simultaneous writer calls.
  perform 1 from atlas.work_items w where w.id in
    (p_downstream_work_item_id,p_prerequisite_work_item_id)
    order by w.id for update;
  select * into v_downstream from atlas.work_items
    where id=p_downstream_work_item_id and organization_id=p_organization_id;
  select * into v_prerequisite from atlas.work_items
    where id=p_prerequisite_work_item_id and organization_id=p_organization_id;

  if v_downstream.id is null or v_prerequisite.id is null then
    raise exception 'Both Work records must belong to the same Organization.'
      using errcode='42501';
  end if;
  if p_enabled and (v_downstream.work_state<>'open' or
     v_prerequisite.work_state not in ('open','completed')) then
    raise exception 'Cannot establish new prerequisites for retired/cancelled Work.'
      using errcode='23514';
  end if;
  -- Withdrawal remains possible for an existing original relation, even if
  -- the Work state changed after the relationship was established.
  if not atlas.work_prerequisite_ledger_scope_v1(
       p_organization_id,p_ledger_id,p_downstream_work_item_id)
     or not atlas.work_prerequisite_ledger_scope_v1(
       p_organization_id,p_ledger_id,p_prerequisite_work_item_id) then
    raise exception 'Both Work records need current relevance to this governing Ledger.'
      using errcode='42501';
  end if;

  select * into v_link from atlas.work_item_relations
  where organization_id=p_organization_id
    and from_work_item_id=p_downstream_work_item_id
    and to_work_item_id=p_prerequisite_work_item_id
    and relation_kind='depends_on' for update;
  v_before:=case when v_link.id is null then null else v_link.active end;
  v_before_satisfied_at:=v_link.satisfied_at;
  if v_link.id is null and p_enabled then
    insert into atlas.work_item_relations(
      organization_id,from_work_item_id,to_work_item_id,relation_kind,active,metadata)
    values(p_organization_id,p_downstream_work_item_id,
      p_prerequisite_work_item_id,'depends_on',true,
      jsonb_build_object('origin','atlas_work_prerequisite_set_v1'))
    returning * into v_link;
    v_applied:=true;
  elsif v_link.id is null and not p_enabled then
    raise exception 'No original prerequisite exists to withdraw.'
      using errcode='P0002';
  elsif v_link.active is distinct from p_enabled then
    update atlas.work_item_relations
    set active=p_enabled,
        -- Withdrawal preserves historical satisfaction; re-enabling requires
        -- fresh evidence and preserves the old timestamp in the event record.
        satisfied_at=case when p_enabled then null else satisfied_at end,
        updated_at=now()
    where id=v_link.id returning * into v_link;
    v_applied:=true;
  end if;

  insert into atlas.work_item_prerequisite_events_v1(
    organization_id,ledger_id,relation_id,
    downstream_work_item_id,prerequisite_work_item_id,
    actor_person_id,source_action_id,request_fingerprint,action_kind,
    before_active,after_active,before_satisfied_at,after_satisfied_at,reason)
  values(p_organization_id,p_ledger_id,v_link.id,
    p_downstream_work_item_id,p_prerequisite_work_item_id,
    v_actor,p_source_action_id,v_fingerprint,
    case when p_enabled then 'establish' else 'withdraw' end,
    v_before,v_link.active,v_before_satisfied_at,v_link.satisfied_at,p_reason)
  returning id into v_event_id;

  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_work_prerequisite_set_v1',
    'relationId',v_link.id,'organizationId',p_organization_id,
    'ledgerId',p_ledger_id,'downstreamWorkItemId',p_downstream_work_item_id,
    'prerequisiteWorkItemId',p_prerequisite_work_item_id,
    'active',v_link.active,'applied',v_applied,'idempotentReplay',false,
    'recordedEventId',v_event_id,
    'doesNotCreateWork',true,'doesNotAutomaticallyBlockWork',true
  );
end;
$$;

-- Independent append-only event readback. An OK mutation receipt alone is
-- insufficient proof that a distinct, actor-attributed event was recorded.
create or replace function atlas.work_prerequisite_event_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_recorded_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
  v_actor uuid;
  v_event atlas.work_item_prerequisite_events_v1%rowtype;
begin
  v_actor:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  select e.* into v_event from atlas.work_item_prerequisite_events_v1 e
  join atlas.work_item_relations r
    on r.id=e.relation_id and r.organization_id=e.organization_id
  where e.id=p_recorded_event_id
    and e.organization_id=p_organization_id
    and e.ledger_id=p_ledger_id
    and r.relation_kind='depends_on'
    and r.from_work_item_id=e.downstream_work_item_id
    and r.to_work_item_id=e.prerequisite_work_item_id
    and atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,e.downstream_work_item_id)
    and atlas.work_prerequisite_ledger_scope_v1(
      p_organization_id,p_ledger_id,e.prerequisite_work_item_id);
  if v_event.id is null then
    raise exception 'No authorized original prerequisite event.' using errcode='42501';
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_work_prerequisite_event_v1',
    'recordedEventId',v_event.id,'relationId',v_event.relation_id,
    'organizationId',v_event.organization_id,'ledgerId',v_event.ledger_id,
    'downstreamWorkItemId',v_event.downstream_work_item_id,
    'prerequisiteWorkItemId',v_event.prerequisite_work_item_id,
    'actorPersonId',v_event.actor_person_id,
    'sourceActionId',v_event.source_action_id,
    'actionKind',v_event.action_kind,
    'afterActive',v_event.after_active,
    'recordedAt',v_event.recorded_at,
    'preservedOriginalReason',v_event.reason
  );
end;
$$;
revoke all on function atlas.work_prerequisite_event_owner_self_api_v1(uuid,uuid,uuid)
  from public,anon,authenticated;

-- Only narrow owner-authorized RPCs are exposed via public. Direct access to
-- canonical Atlas relations and audit rows remains prohibited under RLS.
revoke all on function atlas.work_prerequisite_candidates_owner_self_api_v1(uuid,uuid,integer,uuid)
  from public,anon,authenticated;
revoke all on function atlas.work_prerequisites_owner_self_api_v1(uuid,uuid,uuid)
  from public,anon,authenticated;
revoke all on function atlas.set_work_prerequisite_owner_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)
  from public,anon,authenticated;

create or replace function public.atlas_work_prerequisite_candidates_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_limit integer default 50,
  p_after_work_item_id uuid default null)
returns jsonb language sql stable security definer set search_path=''
as $$ select atlas.work_prerequisite_candidates_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_limit,p_after_work_item_id); $$;
create or replace function public.atlas_work_prerequisites_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_downstream_work_item_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select atlas.work_prerequisites_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_downstream_work_item_id); $$;
create or replace function public.atlas_work_prerequisite_event_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_recorded_event_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$ select atlas.work_prerequisite_event_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_recorded_event_id); $$;
create or replace function public.atlas_set_work_prerequisite_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,
  p_downstream_work_item_id uuid,p_prerequisite_work_item_id uuid,
  p_enabled boolean,p_reason text,p_source_action_id text)
returns jsonb language sql security definer set search_path=''
as $$ select atlas.set_work_prerequisite_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_downstream_work_item_id,
  p_prerequisite_work_item_id,p_enabled,p_reason,p_source_action_id); $$;
revoke all on function public.atlas_work_prerequisite_candidates_self_api_v1(uuid,uuid,integer,uuid)
  from public,anon;
revoke all on function public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)
  from public,anon;
revoke all on function public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)
  from public,anon;
grant execute on function public.atlas_work_prerequisite_candidates_self_api_v1(uuid,uuid,integer,uuid)
  to authenticated;
grant execute on function public.atlas_work_prerequisites_self_api_v1(uuid,uuid,uuid)
  to authenticated;
grant execute on function public.atlas_set_work_prerequisite_self_api_v1(uuid,uuid,uuid,uuid,boolean,text,text)
  to authenticated;
revoke all on function public.atlas_work_prerequisite_event_self_api_v1(uuid,uuid,uuid)
  from public,anon;
grant execute on function public.atlas_work_prerequisite_event_self_api_v1(uuid,uuid,uuid)
  to authenticated;
