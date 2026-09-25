create table atlas.smart_contact_saved_searches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null,
  stable_key text not null,
  name text not null,
  description text null,
  smart_contacts_query jsonb not null check (jsonb_typeof(smart_contacts_query)='object'),
  query_fingerprint text not null,
  max_results integer not null default 100 check (max_results between 1 and 200),
  search_state text not null default 'active' check (search_state in ('active','paused','archived')),
  watch_enabled boolean not null default false,
  watch_cadence text not null default 'manual' check (watch_cadence in ('manual','hourly','daily','weekly')),
  watch_policy jsonb not null default '{"notifyOn":["new","updated","removed"]}'::jsonb
    check (jsonb_typeof(watch_policy)='object'),
  revision integer not null default 1 check (revision > 0),
  last_run_at timestamptz null,
  created_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  updated_by_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint smart_contact_saved_searches_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  unique (organization_id,stable_key)
);

create index smart_contact_saved_searches_org_state_idx
  on atlas.smart_contact_saved_searches(organization_id,search_state,updated_at desc);
create index smart_contact_saved_searches_unit_org_idx
  on atlas.smart_contact_saved_searches(organization_id,organization_unit_id)
  where organization_unit_id is not null;
create index smart_contact_saved_searches_created_membership_idx
  on atlas.smart_contact_saved_searches(created_by_membership_id)
  where created_by_membership_id is not null;
create index smart_contact_saved_searches_updated_membership_idx
  on atlas.smart_contact_saved_searches(updated_by_membership_id)
  where updated_by_membership_id is not null;

create table atlas.smart_contact_saved_search_runs (
  id uuid primary key default gen_random_uuid(),
  saved_search_id uuid not null references atlas.smart_contact_saved_searches(id) on delete cascade,
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  run_number integer not null check (run_number > 0),
  previous_run_id uuid null references atlas.smart_contact_saved_search_runs(id) on delete set null,
  search_revision integer not null check (search_revision > 0),
  run_state text not null default 'running' check (run_state in ('running','completed','failed')),
  query_snapshot jsonb not null check (jsonb_typeof(query_snapshot)='object'),
  query_fingerprint text not null,
  result_count integer not null default 0 check (result_count >= 0),
  new_count integer not null default 0 check (new_count >= 0),
  updated_count integer not null default 0 check (updated_count >= 0),
  removed_count integer not null default 0 check (removed_count >= 0),
  started_at timestamptz not null default now(),
  completed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  unique(saved_search_id,run_number)
);

create index smart_contact_saved_search_runs_search_idx
  on atlas.smart_contact_saved_search_runs(saved_search_id,run_number desc);
create index smart_contact_saved_search_runs_org_idx
  on atlas.smart_contact_saved_search_runs(organization_id,started_at desc);
create index smart_contact_saved_search_runs_previous_idx
  on atlas.smart_contact_saved_search_runs(previous_run_id)
  where previous_run_id is not null;

create table atlas.smart_contact_saved_search_run_items (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.smart_contact_saved_search_runs(id) on delete cascade,
  entity_id uuid not null references local_intel.entities(id) on delete restrict,
  ordinal integer not null check (ordinal > 0),
  relevance_score integer null,
  smart_contact_snapshot jsonb not null check (jsonb_typeof(smart_contact_snapshot)='object'),
  snapshot_fingerprint text not null,
  created_at timestamptz not null default now(),
  unique(run_id,entity_id),
  unique(run_id,ordinal)
);

create index smart_contact_saved_search_run_items_entity_idx
  on atlas.smart_contact_saved_search_run_items(entity_id,run_id);

create table atlas.smart_contact_saved_search_run_deltas (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.smart_contact_saved_search_runs(id) on delete cascade,
  previous_run_id uuid null references atlas.smart_contact_saved_search_runs(id) on delete set null,
  entity_id uuid not null references local_intel.entities(id) on delete restrict,
  change_kind text not null check (change_kind in ('new','updated','removed')),
  current_item_id uuid null references atlas.smart_contact_saved_search_run_items(id) on delete cascade,
  previous_item_id uuid null references atlas.smart_contact_saved_search_run_items(id) on delete set null,
  change_summary jsonb not null default '{}'::jsonb check (jsonb_typeof(change_summary)='object'),
  created_at timestamptz not null default now(),
  unique(run_id,entity_id,change_kind)
);

create index smart_contact_saved_search_run_deltas_kind_idx
  on atlas.smart_contact_saved_search_run_deltas(run_id,change_kind,entity_id);
create index smart_contact_saved_search_run_deltas_previous_run_idx
  on atlas.smart_contact_saved_search_run_deltas(previous_run_id)
  where previous_run_id is not null;
create index smart_contact_saved_search_run_deltas_entity_idx
  on atlas.smart_contact_saved_search_run_deltas(entity_id,run_id);
create index smart_contact_saved_search_run_deltas_current_item_idx
  on atlas.smart_contact_saved_search_run_deltas(current_item_id)
  where current_item_id is not null;
create index smart_contact_saved_search_run_deltas_previous_item_idx
  on atlas.smart_contact_saved_search_run_deltas(previous_item_id)
  where previous_item_id is not null;

alter table atlas.smart_contact_saved_searches enable row level security;
alter table atlas.smart_contact_saved_search_runs enable row level security;
alter table atlas.smart_contact_saved_search_run_items enable row level security;
alter table atlas.smart_contact_saved_search_run_deltas enable row level security;

revoke all on table atlas.smart_contact_saved_searches from public,anon,authenticated;
revoke all on table atlas.smart_contact_saved_search_runs from public,anon,authenticated;
revoke all on table atlas.smart_contact_saved_search_run_items from public,anon,authenticated;
revoke all on table atlas.smart_contact_saved_search_run_deltas from public,anon,authenticated;
grant select,insert,update,delete on table atlas.smart_contact_saved_searches to service_role;
grant select,insert,update,delete on table atlas.smart_contact_saved_search_runs to service_role;
grant select,insert,update,delete on table atlas.smart_contact_saved_search_run_items to service_role;
grant select,insert,update,delete on table atlas.smart_contact_saved_search_run_deltas to service_role;

comment on table atlas.smart_contact_saved_searches is
  'Organization-private reusable Atlas Smart Contacts audience definition. It references canonical reality through a query but does not create canonical truth or an Organization relationship.';
comment on table atlas.smart_contact_saved_search_runs is
  'Frozen-at-completion execution history for a Smart Contacts saved search. Each run snapshots the query revision and dynamic audience.';
comment on table atlas.smart_contact_saved_search_run_items is
  'Frozen Smart Contact members of one saved-search run. The latest completed run is the current dynamic audience.';
comment on table atlas.smart_contact_saved_search_run_deltas is
  'Per-run dynamic-audience change ledger: newly matching, materially updated, or no longer matching entities.';

create or replace function atlas.guard_smart_contact_saved_search_run_update_v1()
returns trigger language plpgsql set search_path=''
as $function$
begin
  if old.run_state in ('completed','failed') and new is distinct from old then
    raise exception 'Completed or failed Smart Contact saved-search runs are immutable.' using errcode='55000';
  end if;
  return new;
end
$function$;

create trigger smart_contact_saved_search_runs_immutable_after_finish_v1
before update on atlas.smart_contact_saved_search_runs
for each row execute function atlas.guard_smart_contact_saved_search_run_update_v1();

create or replace function atlas.guard_smart_contact_saved_search_run_child_write_v1()
returns trigger language plpgsql set search_path=''
as $function$
declare
  v_run_id uuid:=coalesce(new.run_id,old.run_id);
  v_state text;
begin
  select run_state into v_state from atlas.smart_contact_saved_search_runs where id=v_run_id;
  if v_state is null then raise exception 'Saved-search run not found.' using errcode='P0002'; end if;
  if v_state<>'running' then
    raise exception 'Saved-search run contents are immutable after run completion.' using errcode='55000';
  end if;
  return coalesce(new,old);
end
$function$;

create trigger smart_contact_saved_search_run_items_running_only_v1
before insert or update or delete on atlas.smart_contact_saved_search_run_items
for each row execute function atlas.guard_smart_contact_saved_search_run_child_write_v1();

create trigger smart_contact_saved_search_run_deltas_running_only_v1
before insert or update or delete on atlas.smart_contact_saved_search_run_deltas
for each row execute function atlas.guard_smart_contact_saved_search_run_child_write_v1();

create or replace function atlas.create_smart_contact_saved_search_service_v1(
  p_organization_id uuid,
  p_name text,
  p_smart_contacts_query jsonb,
  p_description text default null,
  p_stable_key text default null,
  p_max_results integer default 100,
  p_watch_enabled boolean default false,
  p_watch_cadence text default 'manual',
  p_watch_policy jsonb default '{"notifyOn":["new","updated","removed"]}'::jsonb,
  p_organization_unit_id uuid default null,
  p_actor_membership_id uuid default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_name text:=nullif(btrim(p_name),'');
  v_key text;
  v_search atlas.smart_contact_saved_searches%rowtype;
begin
  if not exists(select 1 from atlas.organizations o where o.id=p_organization_id and o.status='active') then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;
  if v_name is null then raise exception 'Saved search name is required.' using errcode='22023'; end if;
  if p_smart_contacts_query is null or jsonb_typeof(p_smart_contacts_query)<>'object' then
    raise exception 'Smart Contacts query must be an object.' using errcode='22023';
  end if;
  if coalesce(p_max_results,0) not between 1 and 200 then
    raise exception 'max_results must be between 1 and 200.' using errcode='22023';
  end if;
  if coalesce(p_watch_cadence,'') not in ('manual','hourly','daily','weekly') then
    raise exception 'watch_cadence must be manual, hourly, daily, or weekly.' using errcode='22023';
  end if;
  if p_watch_policy is null or jsonb_typeof(p_watch_policy)<>'object' then
    raise exception 'watch_policy must be an object.' using errcode='22023';
  end if;
  if p_organization_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.id=p_organization_unit_id and u.organization_id=p_organization_id
  ) then
    raise exception 'Organization unit does not belong to the Organization.' using errcode='23503';
  end if;
  if p_actor_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_actor_membership_id and m.organization_id=p_organization_id and m.active
  ) then
    raise exception 'Actor membership does not belong to the Organization.' using errcode='42501';
  end if;

  perform atlas.smart_contacts_search_service_v1(p_organization_id,p_smart_contacts_query,1);

  v_key:=nullif(btrim(p_stable_key),'');
  if v_key is null then
    v_key:=trim(both '-' from regexp_replace(lower(v_name),'[^a-z0-9]+','-','g'));
  else
    v_key:=trim(both '-' from regexp_replace(lower(v_key),'[^a-z0-9:_-]+','-','g'));
  end if;
  if v_key='' then v_key:='smart-search-'||substr(replace(gen_random_uuid()::text,'-',''),1,12); end if;

  insert into atlas.smart_contact_saved_searches(
    organization_id,organization_unit_id,stable_key,name,description,
    smart_contacts_query,query_fingerprint,max_results,watch_enabled,watch_cadence,
    watch_policy,created_by_membership_id,updated_by_membership_id
  ) values (
    p_organization_id,p_organization_unit_id,v_key,v_name,nullif(btrim(p_description),''),
    p_smart_contacts_query,md5(p_smart_contacts_query::text),p_max_results,
    p_watch_enabled,p_watch_cadence,p_watch_policy,p_actor_membership_id,p_actor_membership_id
  )
  returning * into v_search;

  return jsonb_build_object(
    'ok',true,'contractVersion','smart_contact_saved_search_v1',
    'savedSearchId',v_search.id,'organizationId',v_search.organization_id,
    'stableKey',v_search.stable_key,'name',v_search.name,'revision',v_search.revision,
    'watchEnabled',v_search.watch_enabled,'watchCadence',v_search.watch_cadence,
    'truthBoundary',jsonb_build_object(
      'organizationPrivateDefinition',true,'sharedIntelligenceMutation',false,
      'organizationRelationshipCreated',false,'communicationAuthorized',false
    )
  );
end
$function$;

create or replace function atlas.update_smart_contact_saved_search_service_v1(
  p_saved_search_id uuid,
  p_expected_revision integer,
  p_name text default null,
  p_description text default null,
  p_smart_contacts_query jsonb default null,
  p_max_results integer default null,
  p_watch_enabled boolean default null,
  p_watch_cadence text default null,
  p_watch_policy jsonb default null,
  p_search_state text default null,
  p_actor_membership_id uuid default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_query jsonb;
begin
  select * into v_search from atlas.smart_contact_saved_searches where id=p_saved_search_id for update;
  if v_search.id is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  if p_expected_revision is null or p_expected_revision<>v_search.revision then
    raise exception 'Saved search revision changed; refresh before editing.' using errcode='40001';
  end if;
  if p_actor_membership_id is not null and not exists(
    select 1 from atlas.organization_memberships m
    where m.id=p_actor_membership_id and m.organization_id=v_search.organization_id and m.active
  ) then raise exception 'Actor membership does not belong to the Organization.' using errcode='42501'; end if;

  v_query:=coalesce(p_smart_contacts_query,v_search.smart_contacts_query);
  if jsonb_typeof(v_query)<>'object' then raise exception 'Smart Contacts query must be an object.' using errcode='22023'; end if;
  if p_smart_contacts_query is not null then
    perform atlas.smart_contacts_search_service_v1(v_search.organization_id,v_query,1);
  end if;
  if p_max_results is not null and p_max_results not between 1 and 200 then
    raise exception 'max_results must be between 1 and 200.' using errcode='22023';
  end if;
  if p_watch_cadence is not null and p_watch_cadence not in ('manual','hourly','daily','weekly') then
    raise exception 'watch_cadence must be manual, hourly, daily, or weekly.' using errcode='22023';
  end if;
  if p_search_state is not null and p_search_state not in ('active','paused','archived') then
    raise exception 'search_state must be active, paused, or archived.' using errcode='22023';
  end if;
  if p_watch_policy is not null and jsonb_typeof(p_watch_policy)<>'object' then
    raise exception 'watch_policy must be an object.' using errcode='22023';
  end if;

  update atlas.smart_contact_saved_searches
  set name=coalesce(nullif(btrim(p_name),''),name),
      description=case when p_description is null then description else nullif(btrim(p_description),'') end,
      smart_contacts_query=v_query,
      query_fingerprint=md5(v_query::text),
      max_results=coalesce(p_max_results,max_results),
      watch_enabled=coalesce(p_watch_enabled,watch_enabled),
      watch_cadence=coalesce(p_watch_cadence,watch_cadence),
      watch_policy=coalesce(p_watch_policy,watch_policy),
      search_state=coalesce(p_search_state,search_state),
      revision=revision+1,
      updated_by_membership_id=coalesce(p_actor_membership_id,updated_by_membership_id),
      updated_at=now()
  where id=v_search.id
  returning * into v_search;

  return jsonb_build_object(
    'ok',true,'contractVersion','smart_contact_saved_search_update_v1',
    'savedSearchId',v_search.id,'revision',v_search.revision,'searchState',v_search.search_state,
    'watchEnabled',v_search.watch_enabled,'watchCadence',v_search.watch_cadence
  );
end
$function$;

create or replace function atlas.run_smart_contact_saved_search_service_v1(p_saved_search_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_previous atlas.smart_contact_saved_search_runs%rowtype;
  v_run atlas.smart_contact_saved_search_runs%rowtype;
  v_payload jsonb;
  v_item jsonb;
  v_ordinal integer:=0;
  v_new integer:=0;
  v_updated integer:=0;
  v_removed integer:=0;
begin
  select * into v_search from atlas.smart_contact_saved_searches where id=p_saved_search_id for update;
  if v_search.id is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  if v_search.search_state='archived' then raise exception 'Archived saved searches cannot run.' using errcode='23514'; end if;

  select * into v_previous
  from atlas.smart_contact_saved_search_runs
  where saved_search_id=v_search.id and run_state='completed'
  order by run_number desc limit 1;

  insert into atlas.smart_contact_saved_search_runs(
    saved_search_id,organization_id,run_number,previous_run_id,search_revision,
    run_state,query_snapshot,query_fingerprint
  ) values (
    v_search.id,v_search.organization_id,coalesce(v_previous.run_number,0)+1,
    v_previous.id,v_search.revision,'running',v_search.smart_contacts_query,v_search.query_fingerprint
  ) returning * into v_run;

  v_payload:=atlas.smart_contacts_search_service_v1(
    v_search.organization_id,v_search.smart_contacts_query,v_search.max_results
  );

  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb))
  loop
    v_ordinal:=v_ordinal+1;
    insert into atlas.smart_contact_saved_search_run_items(
      run_id,entity_id,ordinal,relevance_score,smart_contact_snapshot,snapshot_fingerprint
    ) values (
      v_run.id,(v_item->>'entityId')::uuid,v_ordinal,
      nullif(v_item#>>'{match,relevanceScore}','')::integer,v_item,md5(v_item::text)
    );
  end loop;

  insert into atlas.smart_contact_saved_search_run_deltas(
    run_id,previous_run_id,entity_id,change_kind,current_item_id,previous_item_id,change_summary
  )
  select v_run.id,v_previous.id,c.entity_id,'new',c.id,null,
         jsonb_build_object('currentOrdinal',c.ordinal,'currentScore',c.relevance_score)
  from atlas.smart_contact_saved_search_run_items c
  where c.run_id=v_run.id
    and (v_previous.id is null or not exists(
      select 1 from atlas.smart_contact_saved_search_run_items p
      where p.run_id=v_previous.id and p.entity_id=c.entity_id
    ));
  get diagnostics v_new=row_count;

  if v_previous.id is not null then
    insert into atlas.smart_contact_saved_search_run_deltas(
      run_id,previous_run_id,entity_id,change_kind,current_item_id,previous_item_id,change_summary
    )
    select v_run.id,v_previous.id,c.entity_id,'updated',c.id,p.id,
           jsonb_build_object(
             'priorOrdinal',p.ordinal,'currentOrdinal',c.ordinal,
             'priorScore',p.relevance_score,'currentScore',c.relevance_score,
             'searchDefinitionChanged',v_run.search_revision<>v_previous.search_revision
           )
    from atlas.smart_contact_saved_search_run_items c
    join atlas.smart_contact_saved_search_run_items p
      on p.run_id=v_previous.id and p.entity_id=c.entity_id
    where c.run_id=v_run.id and c.snapshot_fingerprint<>p.snapshot_fingerprint;
    get diagnostics v_updated=row_count;

    insert into atlas.smart_contact_saved_search_run_deltas(
      run_id,previous_run_id,entity_id,change_kind,current_item_id,previous_item_id,change_summary
    )
    select v_run.id,v_previous.id,p.entity_id,'removed',null,p.id,
           jsonb_build_object(
             'priorOrdinal',p.ordinal,'priorScore',p.relevance_score,
             'searchDefinitionChanged',v_run.search_revision<>v_previous.search_revision
           )
    from atlas.smart_contact_saved_search_run_items p
    where p.run_id=v_previous.id and not exists(
      select 1 from atlas.smart_contact_saved_search_run_items c
      where c.run_id=v_run.id and c.entity_id=p.entity_id
    );
    get diagnostics v_removed=row_count;
  end if;

  update atlas.smart_contact_saved_search_runs
  set run_state='completed',result_count=v_ordinal,new_count=v_new,updated_count=v_updated,
      removed_count=v_removed,completed_at=now(),
      metadata=jsonb_build_object(
        'searchDefinitionChanged',
        v_previous.id is not null and v_run.search_revision<>v_previous.search_revision
      )
  where id=v_run.id
  returning * into v_run;

  update atlas.smart_contact_saved_searches
  set last_run_at=v_run.completed_at,updated_at=now()
  where id=v_search.id;

  return jsonb_build_object(
    'ok',true,'contractVersion','smart_contact_saved_search_run_v1',
    'savedSearchId',v_search.id,'runId',v_run.id,'runNumber',v_run.run_number,
    'searchRevision',v_run.search_revision,'resultCount',v_run.result_count,
    'changes',jsonb_build_object('new',v_run.new_count,'updated',v_run.updated_count,'removed',v_run.removed_count),
    'currentAudienceIsLatestCompletedRun',true
  );
end
$function$;

create or replace function atlas.smart_contact_saved_search_service_v1(p_saved_search_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare
  v_search atlas.smart_contact_saved_searches%rowtype;
  v_run atlas.smart_contact_saved_search_runs%rowtype;
  v_items jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
begin
  select * into v_search from atlas.smart_contact_saved_searches where id=p_saved_search_id;
  if v_search.id is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;

  select * into v_run from atlas.smart_contact_saved_search_runs
  where saved_search_id=v_search.id and run_state='completed'
  order by run_number desc limit 1;

  if v_run.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'entityId',i.entity_id,'ordinal',i.ordinal,'relevanceScore',i.relevance_score,
      'smartContact',i.smart_contact_snapshot
    ) order by i.ordinal),'[]'::jsonb)
    into v_items from atlas.smart_contact_saved_search_run_items i where i.run_id=v_run.id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'entityId',d.entity_id,'changeKind',d.change_kind,'changeSummary',d.change_summary
    ) order by case d.change_kind when 'new' then 0 when 'updated' then 1 else 2 end,d.entity_id),'[]'::jsonb)
    into v_changes from atlas.smart_contact_saved_search_run_deltas d where d.run_id=v_run.id;
  end if;

  return jsonb_build_object(
    'contractVersion','smart_contact_saved_search_read_v1',
    'savedSearch',jsonb_build_object(
      'id',v_search.id,'organizationId',v_search.organization_id,
      'organizationUnitId',v_search.organization_unit_id,'stableKey',v_search.stable_key,
      'name',v_search.name,'description',v_search.description,'query',v_search.smart_contacts_query,
      'maxResults',v_search.max_results,'searchState',v_search.search_state,
      'watchEnabled',v_search.watch_enabled,'watchCadence',v_search.watch_cadence,
      'watchPolicy',v_search.watch_policy,'revision',v_search.revision,'lastRunAt',v_search.last_run_at
    ),
    'latestRun',case when v_run.id is null then null else jsonb_build_object(
      'id',v_run.id,'runNumber',v_run.run_number,'previousRunId',v_run.previous_run_id,
      'searchRevision',v_run.search_revision,'resultCount',v_run.result_count,
      'newCount',v_run.new_count,'updatedCount',v_run.updated_count,
      'removedCount',v_run.removed_count,'completedAt',v_run.completed_at,'metadata',v_run.metadata
    ) end,
    'currentAudience',v_items,
    'changesSincePriorRun',v_changes
  );
end
$function$;

create or replace function atlas.smart_contact_saved_searches_service_v1(p_organization_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'stableKey',s.stable_key,'name',s.name,'description',s.description,
    'searchState',s.search_state,'watchEnabled',s.watch_enabled,'watchCadence',s.watch_cadence,
    'revision',s.revision,'lastRunAt',s.last_run_at,
    'latestRun',(
      select jsonb_build_object(
        'id',r.id,'runNumber',r.run_number,'resultCount',r.result_count,
        'newCount',r.new_count,'updatedCount',r.updated_count,'removedCount',r.removed_count,
        'completedAt',r.completed_at
      )
      from atlas.smart_contact_saved_search_runs r
      where r.saved_search_id=s.id and r.run_state='completed'
      order by r.run_number desc limit 1
    )
  ) order by s.name,s.id),'[]'::jsonb)
  from atlas.smart_contact_saved_searches s
  where s.organization_id=p_organization_id and s.search_state<>'archived';
$function$;

create or replace function atlas.create_smart_contact_saved_search_self_api_v1(
  p_organization_id uuid,p_name text,p_smart_contacts_query jsonb,p_description text default null,
  p_stable_key text default null,p_max_results integer default 100,p_watch_enabled boolean default false,
  p_watch_cadence text default 'manual',
  p_watch_policy jsonb default '{"notifyOn":["new","updated","removed"]}'::jsonb,
  p_organization_unit_id uuid default null
)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_membership_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_membership_id:=atlas.current_effective_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'Organization access denied.' using errcode='42501'; end if;
  return atlas.create_smart_contact_saved_search_service_v1(
    p_organization_id,p_name,p_smart_contacts_query,p_description,p_stable_key,
    p_max_results,p_watch_enabled,p_watch_cadence,p_watch_policy,p_organization_unit_id,v_membership_id
  );
end
$function$;

create or replace function atlas.run_smart_contact_saved_search_self_api_v1(p_saved_search_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select organization_id into v_org from atlas.smart_contact_saved_searches where id=p_saved_search_id;
  if v_org is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  if atlas.current_effective_organization_membership_v1(v_org) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.run_smart_contact_saved_search_service_v1(p_saved_search_id);
end
$function$;

create or replace function atlas.smart_contact_saved_search_self_api_v1(p_saved_search_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select organization_id into v_org from atlas.smart_contact_saved_searches where id=p_saved_search_id;
  if v_org is null then raise exception 'Saved search not found.' using errcode='P0002'; end if;
  if atlas.current_effective_organization_membership_v1(v_org) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.smart_contact_saved_search_service_v1(p_saved_search_id);
end
$function$;

create or replace function atlas.smart_contact_saved_searches_self_api_v1(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $function$
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  return atlas.smart_contact_saved_searches_service_v1(p_organization_id);
end
$function$;

revoke all on function atlas.create_smart_contact_saved_search_service_v1(uuid,text,jsonb,text,text,integer,boolean,text,jsonb,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.create_smart_contact_saved_search_service_v1(uuid,text,jsonb,text,text,integer,boolean,text,jsonb,uuid,uuid)
  to service_role;
revoke all on function atlas.update_smart_contact_saved_search_service_v1(uuid,integer,text,text,jsonb,integer,boolean,text,jsonb,text,uuid)
  from public,anon,authenticated;
grant execute on function atlas.update_smart_contact_saved_search_service_v1(uuid,integer,text,text,jsonb,integer,boolean,text,jsonb,text,uuid)
  to service_role;
revoke all on function atlas.run_smart_contact_saved_search_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.run_smart_contact_saved_search_service_v1(uuid) to service_role;
revoke all on function atlas.smart_contact_saved_search_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.smart_contact_saved_search_service_v1(uuid) to service_role;
revoke all on function atlas.smart_contact_saved_searches_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.smart_contact_saved_searches_service_v1(uuid) to service_role;

revoke all on function atlas.create_smart_contact_saved_search_self_api_v1(uuid,text,jsonb,text,text,integer,boolean,text,jsonb,uuid)
  from public,anon;
grant execute on function atlas.create_smart_contact_saved_search_self_api_v1(uuid,text,jsonb,text,text,integer,boolean,text,jsonb,uuid)
  to authenticated;
revoke all on function atlas.run_smart_contact_saved_search_self_api_v1(uuid) from public,anon;
grant execute on function atlas.run_smart_contact_saved_search_self_api_v1(uuid) to authenticated;
revoke all on function atlas.smart_contact_saved_search_self_api_v1(uuid) from public,anon;
grant execute on function atlas.smart_contact_saved_search_self_api_v1(uuid) to authenticated;
revoke all on function atlas.smart_contact_saved_searches_self_api_v1(uuid) from public,anon;
grant execute on function atlas.smart_contact_saved_searches_self_api_v1(uuid) to authenticated;
