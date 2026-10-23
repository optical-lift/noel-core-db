-- Atlas Build 1: original Person capture -> canonical private Collection.
-- Reviewed source candidate only; DO NOT execute against production.
-- Release exclusively through noel-core-db's Atlas migration lane.
begin;

create table atlas.person_collection_filing_events_v1 (
  id uuid primary key default gen_random_uuid(),
  event_sequence bigint generated always as identity unique,
  principal_id uuid not null references atlas.principals(id),
  owner_user_id uuid not null references auth.users(id),
  capture_id uuid not null references atlas.personal_reality_captures(id),
  from_spread_instance_id uuid references atlas.notebook_spread_instances(id),
  to_spread_instance_id uuid not null references atlas.notebook_spread_instances(id),
  binding_id uuid not null references atlas.notebook_spread_source_bindings(id),
  event_kind text not null check (event_kind in ('filed','moved')),
  filing_mode text not null check (filing_mode in ('explicit','approved_rule_v1')),
  rule_key text,
  rule_version integer,
  occurred_at timestamptz not null default clock_timestamp(),
  basis jsonb not null default '{}'::jsonb,
  constraint person_collection_rule_pair_ck check (
    (filing_mode='explicit' and rule_key is null and rule_version is null)
    or (filing_mode='approved_rule_v1'
        and rule_key='measure.body_weight.reported' and rule_version=1)
  )
);
create index person_collection_filing_capture_idx
  on atlas.person_collection_filing_events_v1(principal_id,capture_id,occurred_at desc,id desc);
create index person_collection_filing_today_idx
  on atlas.person_collection_filing_events_v1(principal_id,occurred_at desc,id desc);
alter table atlas.person_collection_filing_events_v1 enable row level security;
revoke all on atlas.person_collection_filing_events_v1 from public,anon,authenticated;
comment on table atlas.person_collection_filing_events_v1 is
  'Append-only source relocation evidence. The original personal_reality_captures row owns testimony; this table never owns another copy.';
create or replace function atlas.reject_person_collection_event_change_v1()
returns trigger language plpgsql set search_path to ''
as $body$
begin
  raise exception 'Collection filing receipts are immutable.' using errcode='42501';
end;
$body$;
revoke all on function atlas.reject_person_collection_event_change_v1() from public,anon,authenticated;
create trigger person_collection_events_immutable_v1
  before update or delete on atlas.person_collection_filing_events_v1
  for each row execute function atlas.reject_person_collection_event_change_v1();

-- Owning Person principal is not the same as Auth user ID; both are checked.
create or replace function atlas.ensure_person_health_collection_v1(p_principal_id uuid)
returns uuid language plpgsql security definer set search_path to ''
as $body$
declare p atlas.principals%rowtype; s atlas.notebook_spread_instances%rowtype;
begin
  select * into p from atlas.principals where id=p_principal_id;
  if p.id is null or p.status<>'active' or p.user_id is null then return null; end if;

  insert into atlas.notebook_spread_instances(
    principal_id,spread_key,scope_kind,scope_id,subject_domain,subject_kind,
    subject_id,purpose_key,horizon_key,thread_key,creation_mode,spread_state,
    title,section_key,composition_contract,basis,metadata
  ) values (
    p.id,'personal.health','person',p.user_id::text,'health','person_body',
    p.id::text,'collection','permanent','personal.health','resolved','open',
    'Health','Private','{}'::jsonb,
    jsonb_build_object('source','atlas.standard_person_collection_v1'),
    jsonb_build_object('privacy','personal','collectionKind','health')
  ) on conflict(principal_id,spread_key) do nothing;

  select * into s from atlas.notebook_spread_instances
    where principal_id=p.id and spread_key='personal.health';
  if s.id is null or s.scope_kind<>'person' or s.scope_id<>p.user_id::text
     or s.subject_domain<>'health' or s.subject_kind<>'person_body'
     or s.subject_id<>p.id::text or s.purpose_key<>'collection'
     or s.horizon_key<>'permanent' or s.spread_state<>'open'
     or s.section_key<>'Private' then
    raise exception 'Canonical private Health Collection identity conflict.' using errcode='23514';
  end if;
  return s.id;
end;
$body$;
revoke all on function atlas.ensure_person_health_collection_v1(uuid) from public,anon,authenticated;

create or replace function atlas.seed_person_health_collection_on_principal_v1()
returns trigger language plpgsql security definer set search_path to ''
as $body$
begin
  if new.status='active' and new.user_id is not null then
    perform atlas.ensure_person_health_collection_v1(new.id);
  end if;
  return new;
end;
$body$;
revoke all on function atlas.seed_person_health_collection_on_principal_v1() from public,anon,authenticated;
create trigger person_health_collection_on_principal_v1
  after insert or update of status,user_id on atlas.principals
  for each row execute function atlas.seed_person_health_collection_on_principal_v1();

-- A supervised backfill changes only the canonical Spread registry; no personal
-- testimony, interpretation, Auth user or Ledger row is fabricated.
do $body$ declare x record; begin
  for x in select id from atlas.principals where status='active' and user_id is not null loop
    perform atlas.ensure_person_health_collection_v1(x.id);
  end loop;
end $body$;

create or replace function atlas.person_collections_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare u uuid:=auth.uid(); p uuid; items jsonb;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  p:=atlas.require_active_task_principal_v1();
  select coalesce(jsonb_agg(jsonb_build_object(
      'spreadInstanceId',s.id,'spreadKey',s.spread_key,'title',s.title,
      'sectionKey',s.section_key,'scopeKind',s.scope_kind,'subjectKind',s.subject_kind,
      'spreadState',s.spread_state
    ) order by s.section_key,s.title,s.id),'[]'::jsonb)
    into items
    from atlas.notebook_spread_instances s
    where s.principal_id=p and s.scope_kind='person' and s.scope_id=u::text
      and s.spread_state='open' and s.purpose_key='collection';
  return jsonb_build_object('ok',true,'contractVersion','person_collections_v1',
    'items',items,'coverage','complete_for_authorized_person_collections',
    'originalSourcesNotDuplicated',true);
end;
$body$;
revoke all on function atlas.person_collections_self_api_v1() from public,anon,authenticated;

create or replace function atlas.person_file_capture_self_api_v1(
  p_capture_id uuid,p_destination_spread_id uuid default null
) returns jsonb language plpgsql security definer set search_path to ''
as $body$
declare
  u uuid:=auth.uid(); p uuid; cap atlas.personal_reality_captures%rowtype;
  dst atlas.notebook_spread_instances%rowtype;
  perm atlas.person_recognition_rule_permissions_v1%rowtype;
  match jsonb; mode text:='explicit';
  previous_id uuid; v_binding_id uuid; receipt_id uuid; change_kind text;
  begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  p:=atlas.require_active_task_principal_v1();
  if p_capture_id is null then raise exception 'Original capture ID required.' using errcode='22023'; end if;

  -- Serialize all moves and duplicate actions against the SAME original row.
  select * into cap from atlas.personal_reality_captures c
    where c.id=p_capture_id and c.owner_user_id=u and c.principal_id=p
      and c.source_surface='personal_notebook_daily_log'
      and c.metadata->>'notebookEntryKind'='raw_note'
      and c.capture_state='captured'
    for update;
  if cap.id is null then raise exception 'Authorized original notebook capture not found.' using errcode='42501'; end if;

  if p_destination_spread_id is null then
    -- No unapproved arbitrary prose routing. Only an EXACT already-approved
    -- rule, with approval time boundary, may choose the standard Health route.
    match:=atlas.recognize_body_weight_sentence_v1(cap.testimony);
    if match is null then
      return jsonb_build_object('ok',true,'routed',false,'captureId',cap.id,
        'reason','unmatched','originalPreserved',true);
    end if;
    select * into perm from atlas.person_recognition_rule_permissions_v1 r
      where r.owner_user_id=u and r.rule_key='measure.body_weight.reported'
        and r.rule_version=1 and r.revoked_at is null
        and (r.approved_capture_id=cap.id or cap.captured_at>=r.approved_at);
    if perm.owner_user_id is null then
      return jsonb_build_object('ok',true,'routed',false,'captureId',cap.id,
        'reason','approval_required_or_source_before_approval','originalPreserved',true);
    end if;
    select * into dst from atlas.notebook_spread_instances s
      where s.principal_id=p and s.spread_key='personal.health';
    mode:='approved_rule_v1';
  else
    select * into dst from atlas.notebook_spread_instances s
      where s.id=p_destination_spread_id;
  end if;

  if dst.id is null or dst.principal_id<>p or dst.scope_kind<>'person'
     or dst.scope_id<>u::text or dst.purpose_key<>'collection'
     or dst.spread_state<>'open' then
    raise exception 'Destination is not an authorized open Personal Collection.' using errcode='42501';
  end if;

  -- Only current private Person-Collection routes take part in a move.
  select b.spread_instance_id into previous_id
    from atlas.notebook_spread_source_bindings b
    join atlas.notebook_spread_instances s on s.id=b.spread_instance_id
    where s.principal_id=p and s.scope_kind='person' and s.scope_id=u::text
      and s.purpose_key='collection'
      and b.source_domain='atlas' and b.source_kind='personal_reality_capture'
      and b.source_id=cap.id::text and b.relationship_kind='memory'
      and b.binding_state='active'
    order by b.created_at,b.id limit 1;

  if previous_id=dst.id then
    select b.id into v_binding_id from atlas.notebook_spread_source_bindings b
    where b.spread_instance_id=dst.id and b.source_domain='atlas'
      and b.source_kind='personal_reality_capture' and b.source_id=cap.id::text
      and b.relationship_kind='memory' and b.binding_state='active';
    select e.id into receipt_id from atlas.person_collection_filing_events_v1 e
      where e.principal_id=p and e.capture_id=cap.id
        and e.to_spread_instance_id=dst.id and e.binding_id=v_binding_id
      order by e.event_sequence desc limit 1;
    if receipt_id is not null then
      return jsonb_build_object('ok',true,'routed',true,'idempotent',true,
        'captureId',cap.id,'receiptId',receipt_id,
        'spreadInstanceId',dst.id,'title',dst.title,'sourcePreserved',true);
    end if;
  end if;

  -- This updates only projection relations, never the testimony source.
  update atlas.notebook_spread_source_bindings b
    set binding_state='retired',retired_at=now(),updated_at=now()
    from atlas.notebook_spread_instances s
    where s.id=b.spread_instance_id and s.principal_id=p
      and s.scope_kind='person' and s.scope_id=u::text
      and s.purpose_key='collection'
      and b.source_domain='atlas' and b.source_kind='personal_reality_capture'
      and b.source_id=cap.id::text and b.relationship_kind='memory'
      and b.binding_state='active' and b.spread_instance_id<>dst.id;

  v_binding_id:=atlas.bind_notebook_spread_source_v1(
    dst.id,'atlas','personal_reality_capture',cap.id::text,'memory','active',
    jsonb_build_object('source','personal_reality_captures','captureId',cap.id),
    jsonb_build_object('filingMode',mode,'ruleKey',
      case when mode='approved_rule_v1' then 'measure.body_weight.reported' else null end)
  );
  change_kind:=case when previous_id is null then 'filed' else 'moved' end;
  insert into atlas.person_collection_filing_events_v1(
    principal_id,owner_user_id,capture_id,from_spread_instance_id,
    to_spread_instance_id,binding_id,event_kind,filing_mode,rule_key,rule_version,basis
  ) values(
    p,u,cap.id,previous_id,dst.id,v_binding_id,change_kind,mode,
    case when mode='approved_rule_v1' then 'measure.body_weight.reported' else null end,
    case when mode='approved_rule_v1' then 1 else null end,
    jsonb_build_object('sourceSurface',cap.source_surface,'sourceCapturedAt',cap.captured_at)
  ) returning id into receipt_id;

  return jsonb_build_object('ok',true,'routed',true,'idempotent',false,
    'captureId',cap.id,'receiptId',receipt_id,'spreadInstanceId',dst.id,
    'title',dst.title,'eventKind',change_kind,'filingMode',mode,
    'sourcePreserved',true);
end;
$body$;
revoke all on function atlas.person_file_capture_self_api_v1(uuid,uuid)
  from public,anon,authenticated;

create or replace function atlas.person_collection_sources_self_api_v1(
  p_spread_instance_id uuid,p_limit integer default 100
) returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare u uuid:=auth.uid(); p uuid; s atlas.notebook_spread_instances%rowtype;
  items jsonb; total_count integer;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'Limit must be 1..100.' using errcode='22023';
  end if;
  p:=atlas.require_active_task_principal_v1();
  select * into s from atlas.notebook_spread_instances x
    where x.id=p_spread_instance_id and x.principal_id=p
      and x.scope_kind='person' and x.scope_id=u::text
      and x.purpose_key='collection' and x.spread_state='open';
  if s.id is null then raise exception 'Authorized Collection not found.' using errcode='42501'; end if;

  with eligible as (
    select c.id as capture_id,c.testimony,c.captured_at,c.evidence_id,
      c.source_surface,c.capture_context,b.id as binding_id,b.created_at as bound_at,
      e.id as receipt_id,e.event_sequence,e.occurred_at as filed_at,e.filing_mode
    from atlas.notebook_spread_source_bindings b
    join atlas.personal_reality_captures c
      on b.source_domain='atlas' and b.source_kind='personal_reality_capture'
      and b.source_id=c.id::text
    join lateral (
      select evt.id,evt.event_sequence,evt.occurred_at,evt.filing_mode
      from atlas.person_collection_filing_events_v1 evt
      where evt.capture_id=c.id and evt.principal_id=p
        and evt.to_spread_instance_id=s.id and evt.binding_id=b.id
      order by evt.event_sequence desc limit 1
    ) e on true
    where b.spread_instance_id=s.id and b.relationship_kind='memory'
      and b.binding_state='active' and c.principal_id=p and c.owner_user_id=u
      and c.capture_state='captured'
      and (e.filing_mode<>'approved_rule_v1' or exists (
        select 1 from atlas.person_recognition_rule_permissions_v1 permission
        where permission.owner_user_id=u
          and permission.rule_key='measure.body_weight.reported'
          and permission.rule_version=1 and permission.revoked_at is null))
  )
  select count(*) into total_count from eligible;

  with eligible as (
    select c.id as capture_id,c.testimony,c.captured_at,c.evidence_id,
      c.source_surface,c.capture_context,b.id as binding_id,
      e.id as receipt_id,e.event_sequence,e.occurred_at as filed_at,e.filing_mode
    from atlas.notebook_spread_source_bindings b
    join atlas.personal_reality_captures c
      on b.source_domain='atlas' and b.source_kind='personal_reality_capture'
      and b.source_id=c.id::text
    join lateral (
      select evt.id,evt.event_sequence,evt.occurred_at,evt.filing_mode from atlas.person_collection_filing_events_v1 evt
      where evt.capture_id=c.id and evt.principal_id=p
        and evt.to_spread_instance_id=s.id and evt.binding_id=b.id
      order by evt.event_sequence desc limit 1
    ) e on true
    where b.spread_instance_id=s.id and b.relationship_kind='memory'
      and b.binding_state='active' and c.principal_id=p and c.owner_user_id=u
      and c.capture_state='captured'
      and (e.filing_mode<>'approved_rule_v1' or exists (
        select 1 from atlas.person_recognition_rule_permissions_v1 permission
        where permission.owner_user_id=u
          and permission.rule_key='measure.body_weight.reported'
          and permission.rule_version=1 and permission.revoked_at is null))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
     'captureId',t.capture_id,'receiptId',t.receipt_id,
     'bindingId',t.binding_id,'testimony',t.testimony,
     'capturedAt',t.captured_at,'filedAt',t.filed_at,
     'evidenceId',t.evidence_id,'sourceSurface',t.source_surface,
     'captureContext',t.capture_context,'filingMode',t.filing_mode)
    order by t.event_sequence desc),'[]'::jsonb) into items
  from (select * from eligible order by event_sequence desc limit p_limit) t;

  return jsonb_build_object('ok',true,'contractVersion','person_collection_sources_v1',
    'spreadInstanceId',s.id,'title',s.title,'items',items,
    'count',total_count,'limit',p_limit,'truncated',total_count>p_limit,
    'coverage',case when total_count>p_limit then 'bounded_partial' else 'complete_for_supported_person_captures' end,
    'sourceOwnedBy','atlas.personal_reality_captures','originalSourcesNotDuplicated',true);
end;
$body$;
revoke all on function atlas.person_collection_sources_self_api_v1(uuid,integer)
  from public,anon,authenticated;

create or replace function atlas.person_today_filing_receipts_self_api_v1(p_date date default null)
returns jsonb language plpgsql stable security definer set search_path to ''
as $body$
declare u uuid:=auth.uid(); p uuid; tz text; local_day date; items jsonb; total_count integer;
begin
  if u is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  p:=atlas.require_active_task_principal_v1();
  select home_timezone into tz from atlas.principals where id=p and user_id=u and status='active';
  if tz is null or not exists(select 1 from pg_catalog.pg_timezone_names where name=tz)
    then raise exception 'Principal timezone unresolved.' using errcode='22023'; end if;
  local_day:=coalesce(p_date,(now() at time zone tz)::date);
  select count(*) into total_count from atlas.person_collection_filing_events_v1 e
    join atlas.notebook_spread_instances s on s.id=e.to_spread_instance_id
    join atlas.notebook_spread_source_bindings b on b.id=e.binding_id
    join atlas.personal_reality_captures c on c.id=e.capture_id
    where e.principal_id=p and e.owner_user_id=u
      and (e.occurred_at at time zone tz)::date=local_day
      and s.principal_id=p and s.scope_kind='person' and s.scope_id=u::text
      and b.binding_state='active' and c.owner_user_id=u and c.principal_id=p
      and s.spread_state='open'
      and e.id=(select latest.id from atlas.person_collection_filing_events_v1 latest
        where latest.principal_id=p and latest.capture_id=c.id
        order by latest.event_sequence desc limit 1)
      and (e.filing_mode<>'approved_rule_v1' or exists(
        select 1 from atlas.person_recognition_rule_permissions_v1 permission
        where permission.owner_user_id=u and permission.rule_key='measure.body_weight.reported'
          and permission.rule_version=1 and permission.revoked_at is null));
  select coalesce(jsonb_agg(jsonb_build_object(
      'receiptId',x.id,'captureId',x.capture_id,
      'spreadInstanceId',x.to_spread_instance_id,'title',x.title,
      'eventKind',x.event_kind,'filedAt',x.occurred_at,
      'fromSpreadInstanceId',x.from_spread_instance_id)
      order by x.event_sequence desc),'[]'::jsonb) into items
  from (
    select e.*,s.title from atlas.person_collection_filing_events_v1 e
    join atlas.notebook_spread_instances s on s.id=e.to_spread_instance_id
    join atlas.notebook_spread_source_bindings b on b.id=e.binding_id
    join atlas.personal_reality_captures c on c.id=e.capture_id
    where e.principal_id=p and e.owner_user_id=u
      and (e.occurred_at at time zone tz)::date=local_day
      and s.principal_id=p and s.scope_kind='person' and s.scope_id=u::text
      and b.binding_state='active' and c.owner_user_id=u and c.principal_id=p
      and s.spread_state='open'
      and e.id=(select latest.id from atlas.person_collection_filing_events_v1 latest
        where latest.principal_id=p and latest.capture_id=c.id
        order by latest.event_sequence desc limit 1)
      and (e.filing_mode<>'approved_rule_v1' or exists(
        select 1 from atlas.person_recognition_rule_permissions_v1 permission
        where permission.owner_user_id=u and permission.rule_key='measure.body_weight.reported'
          and permission.rule_version=1 and permission.revoked_at is null))
    order by e.event_sequence desc limit 100
  ) x;
  return jsonb_build_object('ok',true,
    'contractVersion','person_today_filing_receipts_v1',
    'date',local_day,'timezone',tz,'items',items,'count',total_count,
    'truncated',total_count>100,'sourceTextDuplicated',false);
end;
$body$;
revoke all on function atlas.person_today_filing_receipts_self_api_v1(date)
  from public,anon,authenticated;

-- The only browser-visible RPCs are signed wrappers. The canonical tables and
-- inner definer functions stay unexposed and ungranted.
create or replace function public.person_collections_self_api_v1()
returns jsonb language sql security definer set search_path to ''
as $body$
  select atlas.person_collections_self_api_v1()
$body$;
create or replace function public.person_file_capture_self_api_v1(
  p_capture_id uuid,p_destination_spread_id uuid default null
) returns jsonb language sql security definer set search_path to ''
as $body$
  select atlas.person_file_capture_self_api_v1(p_capture_id,p_destination_spread_id)
$body$;
create or replace function public.person_collection_sources_self_api_v1(
  p_spread_instance_id uuid,p_limit integer default 100
) returns jsonb language sql security definer set search_path to ''
as $body$
  select atlas.person_collection_sources_self_api_v1(p_spread_instance_id,p_limit)
$body$;
create or replace function public.person_today_filing_receipts_self_api_v1(p_date date default null)
returns jsonb language sql security definer set search_path to ''
as $body$
  select atlas.person_today_filing_receipts_self_api_v1(p_date)
$body$;

revoke all on function public.person_collections_self_api_v1() from public,anon;
revoke all on function public.person_file_capture_self_api_v1(uuid,uuid) from public,anon;
revoke all on function public.person_collection_sources_self_api_v1(uuid,integer) from public,anon;
revoke all on function public.person_today_filing_receipts_self_api_v1(date) from public,anon;
grant execute on function public.person_collections_self_api_v1() to authenticated;
grant execute on function public.person_file_capture_self_api_v1(uuid,uuid) to authenticated;
grant execute on function public.person_collection_sources_self_api_v1(uuid,integer) to authenticated;
grant execute on function public.person_today_filing_receipts_self_api_v1(date) to authenticated;

commit;
