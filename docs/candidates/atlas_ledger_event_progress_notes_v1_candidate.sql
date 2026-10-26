-- CANDIDATE ONLY — Gate 5 original Event progress notes.
-- This SQL is deliberately stored as a reviewed candidate, not an applied
-- migration. Promote through the Noel migration workflow AFTER signed
-- connected-Person permission review and exact-SHA integration tests.
--
-- No owner/user-provided freeform note is a task, communication, assignment,
-- approval, payment fact or physical-performance attestation.
begin;

create table atlas.ledger_event_progress_notes_v1 (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id),
  ledger_id uuid not null references ledger.ledgers(id),
  occurrence_id uuid not null references local_intel.occurrences(id),
  work_item_id uuid null references atlas.work_items(id),
  author_person_id uuid not null references reality.entities(id),
  source_action_id text not null check (length(btrim(source_action_id)) between 1 and 128),
  body text not null check (length(btrim(body)) between 3 and 4000),
  recorded_at timestamptz not null default now(),
  unique (ledger_id,occurrence_id,source_action_id)
);
create index ledger_event_progress_notes_read_v1
 on atlas.ledger_event_progress_notes_v1
 (organization_id,ledger_id,occurrence_id,recorded_at desc,id desc);
alter table atlas.ledger_event_progress_notes_v1 enable row level security;
revoke all on atlas.ledger_event_progress_notes_v1 from public,anon,authenticated;
comment on table atlas.ledger_event_progress_notes_v1 is
 'Append-only original Event progress observations; not task outcomes, messages, or approvals. Read and append only via exact-Event signed Person APIs.';

create function atlas.record_ledger_event_progress_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_work_item_id uuid,p_body text,p_source_action_id text
) returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
  v_actor uuid;
  v_body text:=nullif(btrim(coalesce(p_body,'')),'');
  v_key text:=nullif(btrim(coalesce(p_source_action_id,'')),'');
  v_note atlas.ledger_event_progress_notes_v1%rowtype;
  v_created boolean:=false;
begin
  if p_organization_id is null or p_ledger_id is null or p_occurrence_id is null
     or length(coalesce(v_body,'')) not between 3 and 4000
     or length(coalesce(v_key,'')) not between 1 and 128 then
    raise exception 'Exact Event, progress text and stable source action required'
      using errcode='22023';
  end if;

  -- Same native connected-Person source guard used by existing bound Event
  -- reads and actions, including active organization / occurrence binding.
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if v_actor is null then
    raise exception 'Signed connected Person required' using errcode='42501';
  end if;
  if p_work_item_id is not null then
    perform atlas.assert_ledger_occurrence_work_link_v1(
      p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id);
    -- Historical Event links may still exist after their current Event
    -- association is removed. Preserve old notes; don't append new progress
    -- to a Work item withdrawn from this Event.
    if exists(select 1 from atlas.ledger_occurrence_work_actions_v1 removed
      where removed.organization_id=p_organization_id
        and removed.ledger_id=p_ledger_id
        and removed.occurrence_id=p_occurrence_id
        and removed.work_item_id=p_work_item_id
        and removed.action_kind='removed') then
      raise exception 'Work has been removed from this Event; new Work-specific progress is not admitted'
        using errcode='23514';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.event.progress:'||p_ledger_id::text||':'||
    p_occurrence_id::text||':'||v_key,0));
  select * into v_note from atlas.ledger_event_progress_notes_v1 n
   where n.ledger_id=p_ledger_id and n.occurrence_id=p_occurrence_id
     and n.source_action_id=v_key;
  if v_note.id is not null then
    if v_note.organization_id<>p_organization_id
       or v_note.author_person_id<>v_actor
       or v_note.work_item_id is distinct from p_work_item_id
       or v_note.body<>v_body then
      raise exception 'Progress action identity belongs to another observation'
        using errcode='23505';
    end if;
  else
    insert into atlas.ledger_event_progress_notes_v1(
      organization_id,ledger_id,occurrence_id,work_item_id,
      author_person_id,source_action_id,body)
    values(p_organization_id,p_ledger_id,p_occurrence_id,
      p_work_item_id,v_actor,v_key,v_body)
    returning * into v_note;
    v_created:=true;
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_event_progress_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'occurrenceId',p_occurrence_id,'workItemId',p_work_item_id,
    'noteId',v_note.id,'authorPersonId',v_actor,
    'created',v_created,'idempotent',not v_created,
    'newWorkCreated',false,'responsibilityChanged',false,
    'communicationSent',false,'approvalGranted',false);
end $fn$;

create function atlas.ledger_event_progress_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_work_item_id uuid default null,
  p_after_recorded_at timestamptz default null,
  p_after_note_id uuid default null,
  p_exact_note_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_actor uuid;
  v_items jsonb;
  v_more boolean:=false;
  v_last_at timestamptz;
  v_last_id uuid;
  v_count int;
begin
  if p_organization_id is null or p_ledger_id is null or p_occurrence_id is null
     or ((p_after_recorded_at is null)<>(p_after_note_id is null))
     or (p_exact_note_id is not null and p_after_note_id is not null) then
    raise exception 'Exact Event and valid source cursor required' using errcode='22023';
  end if;
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  if v_actor is null then
    raise exception 'Signed connected Person required' using errcode='42501';
  end if;
  if p_work_item_id is not null then
    perform atlas.assert_ledger_occurrence_work_link_v1(
      p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id);
  end if;

  with page as materialized (
    select n.id,n.work_item_id,n.author_person_id,n.body,n.recorded_at,
       author.display_name as author_name
    from atlas.ledger_event_progress_notes_v1 n
    join reality.entities author on author.id=n.author_person_id
       and author.entity_kind='person' and author.identity_state='canonical'
    where n.organization_id=p_organization_id and n.ledger_id=p_ledger_id
      and n.occurrence_id=p_occurrence_id
      and (p_work_item_id is null or n.work_item_id=p_work_item_id)
      and (p_exact_note_id is null or n.id=p_exact_note_id)
      and (p_after_recorded_at is null or
        (n.recorded_at,n.id)<(p_after_recorded_at,p_after_note_id))
    order by n.recorded_at desc,n.id desc
    limit 51
  ), visible as materialized (
    select * from page order by recorded_at desc,id desc limit 50
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
      'noteId',q.id,'workItemId',q.work_item_id,
      'authorPersonId',q.author_person_id,
      'authorName',q.author_name,'body',q.body,
      'recordedAt',q.recorded_at) order by q.recorded_at desc,q.id desc)
      from visible q),'[]'::jsonb),
    (select count(*)>50 from page),
    (select count(*) from visible),
    (select recorded_at from visible order by recorded_at,id limit 1),
    (select id from visible order by recorded_at,id limit 1)
  into v_items,v_more,v_count,v_last_at,v_last_id;

  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_event_progress_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'occurrenceId',p_occurrence_id,
    'items',v_items,'hasMore',v_more,
    'nextRecordedAt',case when v_more then v_last_at else null end,
    'nextNoteId',case when v_more then v_last_id else null end,
    'appendOnly',true,'communicationEventsIncluded',false,
    'doesNotAssertPhysicalPerformance',true);
end $fn$;

revoke all on function
  atlas.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function
  atlas.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)
  from public,anon,authenticated;
-- The public forwarding functions execute under authenticated, just like
-- current signed Atlas RPC adapters. Internal functions recheck exact source.
grant execute on function
  atlas.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)
  to authenticated;
grant execute on function
  atlas.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)
  to authenticated;

-- Existing exposed browser API pattern: explicit minimal invoker forwarding.
create function public.record_ledger_event_progress_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_work_item_id uuid,p_body text,p_source_action_id text
) returns jsonb language sql volatile security invoker set search_path to ''
as $fn$
 select atlas.record_ledger_event_progress_self_api_v1(
   p_organization_id,p_ledger_id,p_occurrence_id,
   p_work_item_id,p_body,p_source_action_id)
$fn$;

create function public.ledger_event_progress_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,
  p_work_item_id uuid default null,
  p_after_recorded_at timestamptz default null,
  p_after_note_id uuid default null,
  p_exact_note_id uuid default null
) returns jsonb language sql stable security invoker set search_path to ''
as $fn$
 select atlas.ledger_event_progress_self_api_v1(
   p_organization_id,p_ledger_id,p_occurrence_id,p_work_item_id,
   p_after_recorded_at,p_after_note_id,p_exact_note_id)
$fn$;

revoke all on function
  public.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)
  from public,anon,authenticated;
revoke all on function
  public.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)
  from public,anon,authenticated;
grant execute on function
  public.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)
  to authenticated;
grant execute on function
  public.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)
  to authenticated;
commit;

-- Pre-promotion SQL acceptance (signed-session testing required):
-- 1. unauthenticated call fails (no anonymous EXECUTE grant).
-- 2. signed nonparticipant cannot see the Event or append a note.
-- 3. signed connected Person can append to exact original Event.
-- 4. same action ID + same body returns identical note ID (idempotent).
-- 5. same action ID + changed body/author/Work fails.
-- 6. Work ID unrelated to the exact Event fails.
-- 7. older notes paginate by (recorded_at,id) without duplicates.
-- 8. correcting a note appends a new note; no UPDATE/DELETE path exists.
-- 9. different signed Persons see the same original Event timeline.
-- 10. note never creates Work, assignment, approvals or email receipts.
