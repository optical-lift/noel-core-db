begin;

-- Stage 5 finishing program:
-- exact-event Reply All / Forward, internal collaboration, personal follow-up,
-- draft collision safety, and durable composition provenance.

alter table atlas.communication_email_drafts
  add column if not exists composition_kind text not null default 'compose',
  add column if not exists source_communication_event_id uuid references atlas.communication_events(id) on delete restrict;

alter table atlas.communication_outbound_operations
  add column if not exists composition_kind text not null default 'compose',
  add column if not exists source_communication_event_id uuid references atlas.communication_events(id) on delete restrict;

update atlas.communication_email_drafts
set composition_kind='reply',
    source_communication_event_id=reply_to_communication_event_id
where reply_to_communication_event_id is not null
  and source_communication_event_id is null;

update atlas.communication_outbound_operations
set composition_kind='reply',
    source_communication_event_id=reply_to_communication_event_id
where reply_to_communication_event_id is not null
  and source_communication_event_id is null;

alter table atlas.communication_email_drafts
  drop constraint if exists communication_email_drafts_composition_kind_check;
alter table atlas.communication_email_drafts
  add constraint communication_email_drafts_composition_kind_check
  check (composition_kind in ('compose','reply','reply_all','forward'));

alter table atlas.communication_outbound_operations
  drop constraint if exists communication_outbound_operations_composition_kind_check;
alter table atlas.communication_outbound_operations
  add constraint communication_outbound_operations_composition_kind_check
  check (composition_kind in ('compose','reply','reply_all','forward'));

create or replace function atlas.guard_communication_composition_provenance_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_common_id uuid;
  v_endpoint_id uuid;
begin
  if new.composition_kind='compose'
     and new.reply_to_communication_event_id is not null
     and new.source_communication_event_id is null then
    new.composition_kind:='reply';
    new.source_communication_event_id:=new.reply_to_communication_event_id;
  end if;

  if new.composition_kind='compose' then
    if new.source_communication_event_id is not null or new.reply_to_communication_event_id is not null then
      raise exception 'Compose cannot claim source-Event provenance.' using errcode='23514';
    end if;
    return new;
  end if;

  if new.source_communication_event_id is null then
    raise exception 'Reply, Reply All, and Forward require an exact source Communication Event.' using errcode='23514';
  end if;

  if new.composition_kind in ('reply','reply_all') then
    if new.reply_to_communication_event_id is distinct from new.source_communication_event_id then
      raise exception 'Reply provenance must use the exact source Event as the reply target.' using errcode='23514';
    end if;
  elsif new.composition_kind='forward' and new.reply_to_communication_event_id is not null then
    raise exception 'Forward preserves source Event provenance without reply-thread transport semantics.' using errcode='23514';
  end if;

  select membership.communication_conversation_id,membership.communication_endpoint_id
  into v_common_id,v_endpoint_id
  from atlas.communication_conversation_events membership
  where membership.communication_event_id=new.source_communication_event_id
  limit 1;

  if v_common_id is null then
    raise exception 'Source Communication Event is not attached to a common Communication Conversation.' using errcode='23514';
  end if;
  -- Compatibility storage inserts may receive the common Conversation ID in the
  -- immediately following command-membrane update. Direct browser table writes are
  -- unavailable; enforce the common identity as soon as it is present.
  if new.communication_conversation_id is null then
    return new;
  end if;
  if new.communication_conversation_id is distinct from v_common_id then
    raise exception 'Composition source Event belongs to another Communication Conversation.' using errcode='23514';
  end if;
  if new.communication_endpoint_id is distinct from v_endpoint_id then
    raise exception 'Composition must preserve the exact Communication Endpoint of the source Event.' using errcode='42501';
  end if;

  return new;
end;
$function$;

drop trigger if exists communication_email_drafts_composition_guard_v1 on atlas.communication_email_drafts;
create trigger communication_email_drafts_composition_guard_v1
before insert or update of composition_kind,source_communication_event_id,reply_to_communication_event_id,communication_conversation_id,communication_endpoint_id
on atlas.communication_email_drafts
for each row execute function atlas.guard_communication_composition_provenance_v1();

drop trigger if exists communication_outbound_operations_composition_guard_v1 on atlas.communication_outbound_operations;
create trigger communication_outbound_operations_composition_guard_v1
before insert or update of composition_kind,source_communication_event_id,reply_to_communication_event_id,communication_conversation_id,communication_endpoint_id
on atlas.communication_outbound_operations
for each row execute function atlas.guard_communication_composition_provenance_v1();

create table if not exists atlas.communication_conversation_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  author_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  body text not null check (btrim(body)<>'' and char_length(body)<=10000),
  note_state text not null default 'active' check (note_state in ('active','retracted')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retracted_at timestamptz,
  check ((note_state='retracted')=(retracted_at is not null))
);

create index if not exists communication_conversation_notes_conversation_idx
on atlas.communication_conversation_notes(communication_conversation_id,created_at,id);

create table if not exists atlas.communication_conversation_note_mentions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  note_id uuid not null references atlas.communication_conversation_notes(id) on delete cascade,
  mentioned_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  mentioned_by_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  mention_state text not null default 'active' check (mention_state in ('active','retracted')),
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  unique(note_id,mentioned_membership_id)
);

create index if not exists communication_conversation_mentions_attention_idx
on atlas.communication_conversation_note_mentions(mentioned_membership_id,mention_state,acknowledged_at,created_at);

create table if not exists atlas.communication_conversation_followups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  due_at timestamptz not null,
  note text,
  followup_state text not null default 'scheduled' check (followup_state in ('scheduled','completed','cancelled')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  check (
    (followup_state='scheduled' and completed_at is null and cancelled_at is null)
    or (followup_state='completed' and completed_at is not null and cancelled_at is null)
    or (followup_state='cancelled' and cancelled_at is not null and completed_at is null)
  )
);

create unique index if not exists communication_conversation_followups_one_scheduled_idx
on atlas.communication_conversation_followups(communication_conversation_id,membership_id)
where followup_state='scheduled';

create index if not exists communication_conversation_followups_due_idx
on atlas.communication_conversation_followups(membership_id,followup_state,due_at);

create table if not exists atlas.communication_conversation_activity_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  communication_conversation_id uuid not null references atlas.communication_conversations(id) on delete cascade,
  actor_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  target_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  communication_event_id uuid references atlas.communication_events(id) on delete restrict,
  note_id uuid references atlas.communication_conversation_notes(id) on delete restrict,
  followup_id uuid references atlas.communication_conversation_followups(id) on delete restrict,
  draft_id uuid references atlas.communication_email_drafts(id) on delete restrict,
  event_kind text not null check (btrim(event_kind)<>'' and char_length(event_kind)<=80),
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object')
);

create index if not exists communication_conversation_activity_timeline_idx
on atlas.communication_conversation_activity_events(communication_conversation_id,occurred_at,id);

create or replace function atlas.reject_communication_conversation_activity_mutation_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Communication Conversation activity is append-only.';
end;
$function$;

drop trigger if exists communication_conversation_activity_append_only_v1 on atlas.communication_conversation_activity_events;
create trigger communication_conversation_activity_append_only_v1
before update or delete on atlas.communication_conversation_activity_events
for each row execute function atlas.reject_communication_conversation_activity_mutation_v1();

alter table atlas.communication_conversation_notes enable row level security;
alter table atlas.communication_conversation_note_mentions enable row level security;
alter table atlas.communication_conversation_followups enable row level security;
alter table atlas.communication_conversation_activity_events enable row level security;

revoke all on atlas.communication_conversation_notes from public,anon,authenticated;
revoke all on atlas.communication_conversation_note_mentions from public,anon,authenticated;
revoke all on atlas.communication_conversation_followups from public,anon,authenticated;
revoke all on atlas.communication_conversation_activity_events from public,anon,authenticated;
grant all on atlas.communication_conversation_notes to service_role;
grant all on atlas.communication_conversation_note_mentions to service_role;
grant all on atlas.communication_conversation_followups to service_role;
grant all on atlas.communication_conversation_activity_events to service_role;

create or replace function atlas.communication_conversation_actor_context_self_v1(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_org uuid;
  v_member uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if not atlas.organization_correspondence_read_authorized_self_v1(p_communication_conversation_id) then
    raise exception 'Communication Conversation read authority required.' using errcode='42501';
  end if;
  v_org:=atlas.organization_correspondence_effective_organization_v1(p_communication_conversation_id);
  v_member:=atlas.current_effective_organization_membership_v1(v_org);
  if v_org is null or v_member is null then
    raise exception 'Active Organization membership required.' using errcode='42501';
  end if;
  return jsonb_build_object('organizationId',v_org,'membershipId',v_member);
end;
$function$;

create or replace function atlas.organization_correspondence_recipient_proposal_self_api_v1(
  p_communication_conversation_id uuid,
  p_communication_event_id uuid,
  p_mode text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_mode text:=lower(btrim(coalesce(p_mode,'')));
  v_event atlas.communication_events%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_event_common uuid;
  v_endpoint_id uuid;
  v_subject text;
  v_to jsonb:='[]'::jsonb;
  v_cc jsonb:='[]'::jsonb;
  v_sender jsonb:='[]'::jsonb;
  v_nonself_to jsonb:='[]'::jsonb;
  v_nonself_cc jsonb:='[]'::jsonb;
  v_endpoint_address text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_mode not in ('reply','reply_all','forward') then
    raise exception 'Composition mode must be reply, reply_all, or forward.' using errcode='22023';
  end if;
  if not atlas.organization_correspondence_read_authorized_self_v1(p_communication_conversation_id) then
    raise exception 'Communication Conversation read authority required.' using errcode='42501';
  end if;

  select membership.communication_conversation_id,membership.communication_endpoint_id
  into v_event_common,v_endpoint_id
  from atlas.communication_conversation_events membership
  where membership.communication_event_id=p_communication_event_id
  limit 1;

  select * into v_event
  from atlas.communication_events event
  where event.id=p_communication_event_id;

  if v_event.id is null or v_event_common is distinct from p_communication_conversation_id then
    raise exception 'Exact source Event is not part of this Communication Conversation.' using errcode='42501';
  end if;

  select * into v_endpoint from atlas.communication_endpoints
  where id=v_endpoint_id and endpoint_state='active';

  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then
    raise exception 'Exact source Event does not belong to an active email Endpoint.' using errcode='22023';
  end if;
  if v_mode in ('reply','reply_all') and v_event.direction<>'incoming' then
    raise exception 'Reply recipients are proposed only from an incoming Communication Event.' using errcode='22023';
  end if;

  v_endpoint_address:=lower(btrim(coalesce(v_endpoint.address,'')));

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'address',q.address,
    'name',q.display_name
  )) order by q.first_id),'[]'::jsonb)
  into v_sender
  from (
    select lower(btrim(p.address)) as key,min(p.id::text) as first_id,
           min(p.address) as address,
           max(nullif(btrim(p.metadata->>'displayName'),'')) as display_name
    from atlas.communication_event_participants p
    where p.communication_event_id=v_event.id
      and p.address_kind='email'
      and p.participant_role in ('sender','from')
      and not p.is_self
      and btrim(p.address)<>''
      and lower(btrim(p.address))<>v_endpoint_address
    group by lower(btrim(p.address))
  ) q;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'address',q.address,
    'name',q.display_name
  )) order by q.first_id),'[]'::jsonb)
  into v_nonself_to
  from (
    select lower(btrim(p.address)) as key,min(p.id::text) as first_id,
           min(p.address) as address,
           max(nullif(btrim(p.metadata->>'displayName'),'')) as display_name
    from atlas.communication_event_participants p
    where p.communication_event_id=v_event.id
      and p.address_kind='email'
      and p.participant_role='to'
      and not p.is_self
      and btrim(p.address)<>''
      and lower(btrim(p.address))<>v_endpoint_address
    group by lower(btrim(p.address))
  ) q;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'address',q.address,
    'name',q.display_name
  )) order by q.first_id),'[]'::jsonb)
  into v_nonself_cc
  from (
    select lower(btrim(p.address)) as key,min(p.id::text) as first_id,
           min(p.address) as address,
           max(nullif(btrim(p.metadata->>'displayName'),'')) as display_name
    from atlas.communication_event_participants p
    where p.communication_event_id=v_event.id
      and p.address_kind='email'
      and p.participant_role='cc'
      and not p.is_self
      and btrim(p.address)<>''
      and lower(btrim(p.address))<>v_endpoint_address
    group by lower(btrim(p.address))
  ) q;

  if v_mode='reply' then
    v_to:=v_sender;
  elsif v_mode='reply_all' then
    select coalesce(jsonb_agg(item order by ord),'[]'::jsonb) into v_to
    from (
      select distinct on (lower(item->>'address')) item,ord
      from (
        select item,ord from jsonb_array_elements(v_sender) with ordinality s(item,ord)
        union all
        select item,100000+ord from jsonb_array_elements(v_nonself_to) with ordinality t(item,ord)
      ) all_to
      where nullif(btrim(item->>'address'),'') is not null
      order by lower(item->>'address'),ord
    ) dedup;

    select coalesce(jsonb_agg(item order by ord),'[]'::jsonb) into v_cc
    from (
      select item,ord
      from jsonb_array_elements(v_nonself_cc) with ordinality c(item,ord)
      where not exists (
        select 1 from jsonb_array_elements(v_to) t
        where lower(t->>'address')=lower(item->>'address')
      )
    ) cc_only;
  end if;

  select subject into v_subject
  from atlas.communication_conversations
  where id=p_communication_conversation_id;

  if v_mode in ('reply','reply_all') then
    if jsonb_array_length(v_to)=0 then
      raise exception 'Exact source Event has no non-self sender available for reply.' using errcode='22023';
    end if;
    if lower(coalesce(v_subject,'')) !~ '^re:' then
      v_subject:='Re: '||coalesce(nullif(v_subject,''),'Correspondence');
    end if;
  elsif v_mode='forward' then
    if lower(coalesce(v_subject,'')) !~ '^(fwd|fw):' then
      v_subject:='Fwd: '||coalesce(nullif(v_subject,''),'Correspondence');
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_recipient_proposal_v1',
    'identityRoot','communication_conversation',
    'communicationConversationId',p_communication_conversation_id,
    'sourceCommunicationEventId',v_event.id,
    'communicationEndpointId',v_endpoint.id,
    'mode',v_mode,
    'to',v_to,
    'cc',v_cc,
    'bcc','[]'::jsonb,
    'subject',v_subject,
    'sourceAttachmentIds',coalesce((
      select jsonb_agg(a.id order by a.created_at,a.id)
      from atlas.communication_attachments a
      where a.event_id=v_event.id
    ),'[]'::jsonb)
  );
end;
$function$;

create or replace function atlas.save_communication_email_draft_self_api_v3(
  p_draft_id uuid,
  p_communication_endpoint_id uuid,
  p_communication_conversation_id uuid,
  p_source_communication_event_id uuid,
  p_composition_kind text,
  p_to_recipients jsonb,
  p_cc_recipients jsonb,
  p_bcc_recipients jsonb,
  p_subject text,
  p_body_text text,
  p_body_html text,
  p_attachment_refs jsonb,
  p_signature_id uuid,
  p_send_after timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_kind text:=lower(btrim(coalesce(p_composition_kind,'compose')));
  v_reply_event uuid;
  v_result jsonb;
  v_id uuid;
  v_existing_id uuid;
begin
  if v_kind not in ('compose','reply','reply_all','forward') then
    raise exception 'Unsupported composition kind.' using errcode='22023';
  end if;
  if v_kind='compose' and p_source_communication_event_id is not null then
    raise exception 'New composition cannot claim a source Event.' using errcode='22023';
  end if;
  if v_kind<>'compose' and p_source_communication_event_id is null then
    raise exception 'Reply, Reply All, and Forward require an exact source Event.' using errcode='22023';
  end if;
  v_reply_event:=case when v_kind in ('reply','reply_all') then p_source_communication_event_id else null end;

  if p_draft_id is not null and exists(
    select 1 from atlas.communication_email_drafts where id=p_draft_id
  ) then
    v_existing_id:=p_draft_id;
  end if;

  v_result:=atlas.save_communication_email_draft_self_api_v2(
    v_existing_id,p_communication_endpoint_id,p_communication_conversation_id,v_reply_event,
    p_to_recipients,p_cc_recipients,p_bcc_recipients,p_subject,p_body_text,p_body_html,
    p_attachment_refs,p_signature_id,p_send_after,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'compositionKind',v_kind,
      'sourceCommunicationEventId',p_source_communication_event_id
    )
  );
  v_id=(v_result->>'draftId')::uuid;

  update atlas.communication_email_drafts
  set composition_kind=v_kind,
      source_communication_event_id=p_source_communication_event_id,
      metadata=metadata||jsonb_build_object(
        'compositionKind',v_kind,
        'sourceCommunicationEventId',p_source_communication_event_id
      ),
      updated_at=now()
  where id=v_id;

  return v_result||jsonb_build_object(
    'contractVersion','communication_email_draft_v4',
    'compositionKind',v_kind,
    'sourceCommunicationEventId',p_source_communication_event_id
  );
end;
$function$;

create or replace function atlas.bind_communication_outbound_composition_from_draft_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.authorized_outbound_operation_id is not null
     and new.authorized_outbound_operation_id is distinct from old.authorized_outbound_operation_id then
    update atlas.communication_outbound_operations
    set composition_kind=new.composition_kind,
        source_communication_event_id=new.source_communication_event_id,
        metadata=metadata||jsonb_build_object(
          'compositionKind',new.composition_kind,
          'sourceCommunicationEventId',new.source_communication_event_id,
          'compositionProvenance','communication_email_draft'
        ),
        updated_at=now()
    where id=new.authorized_outbound_operation_id;
  end if;
  return new;
end;
$function$;

drop trigger if exists communication_email_drafts_bind_outbound_composition_v1 on atlas.communication_email_drafts;
create trigger communication_email_drafts_bind_outbound_composition_v1
after update of authorized_outbound_operation_id on atlas.communication_email_drafts
for each row execute function atlas.bind_communication_outbound_composition_from_draft_v1();

create or replace function atlas.organization_correspondence_drafts_self_api_v2(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_communication_conversation_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.organization_correspondence_drafts_self_api_v1(
    p_organization_id,p_communication_endpoint_id,p_communication_conversation_id,p_limit
  );

  select coalesce(jsonb_agg(
    item||jsonb_build_object(
      'compositionKind',draft.composition_kind,
      'sourceCommunicationEventId',draft.source_communication_event_id,
      'takeoverAllowed',
        not coalesce((item->>'isMine')::boolean,false)
        and draft.draft_state='active'
        and atlas.communication_endpoint_authorized_self_v1(draft.communication_endpoint_id,'send')
    )
    order by draft.updated_at desc,draft.id
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item
  join atlas.communication_email_drafts draft on draft.id=(item->>'draftId')::uuid;

  return (v_base-'items')||jsonb_build_object(
    'contractVersion','organization_correspondence_drafts_v2',
    'items',v_items
  );
end;
$function$;

create or replace function atlas.record_communication_conversation_note_self_api_v1(
  p_communication_conversation_id uuid,
  p_body text,
  p_mentioned_membership_ids jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_org uuid;
  v_member uuid;
  v_note_id uuid;
  v_target_text text;
  v_target uuid;
  v_mentions jsonb:='[]'::jsonb;
begin
  if btrim(coalesce(p_body,''))='' or char_length(p_body)>10000 then
    raise exception 'Internal note must contain between 1 and 10000 characters.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_mentioned_membership_ids,'[]'::jsonb))<>'array' then
    raise exception 'Mentioned memberships must be an array.' using errcode='22023';
  end if;

  v_context:=atlas.communication_conversation_actor_context_self_v1(p_communication_conversation_id);
  v_org=(v_context->>'organizationId')::uuid;
  v_member=(v_context->>'membershipId')::uuid;

  insert into atlas.communication_conversation_notes(
    organization_id,communication_conversation_id,author_membership_id,body,metadata
  ) values (
    v_org,p_communication_conversation_id,v_member,p_body,
    jsonb_build_object('visibility','internal_only','identityRoot','communication_conversation')
  ) returning id into v_note_id;

  for v_target_text in
    select distinct value #>> '{}'
    from jsonb_array_elements(coalesce(p_mentioned_membership_ids,'[]'::jsonb))
  loop
    begin
      v_target:=v_target_text::uuid;
    exception when invalid_text_representation then
      raise exception 'Mention target is not a valid membership identifier.' using errcode='22023';
    end;
    if v_target=v_member then continue; end if;
    if not exists(
      select 1
      from atlas.organization_memberships membership
      where membership.id=v_target
        and membership.organization_id=v_org
        and membership.active
        and exists(
          select 1
          from atlas.communication_conversation_endpoints conversation_endpoint
          where conversation_endpoint.communication_conversation_id=p_communication_conversation_id
            and atlas.communication_endpoint_membership_has_capability_v1(
              conversation_endpoint.communication_endpoint_id,v_target,'view'
            )
        )
    ) then
      raise exception 'Mention target is not an active member with access to this Communication Conversation.' using errcode='42501';
    end if;
    insert into atlas.communication_conversation_note_mentions(
      organization_id,communication_conversation_id,note_id,
      mentioned_membership_id,mentioned_by_membership_id
    ) values (
      v_org,p_communication_conversation_id,v_note_id,v_target,v_member
    ) on conflict(note_id,mentioned_membership_id) do nothing;
    v_mentions:=v_mentions||jsonb_build_array(v_target);
  end loop;

  insert into atlas.communication_conversation_activity_events(
    organization_id,communication_conversation_id,actor_membership_id,note_id,event_kind,metadata
  ) values (
    v_org,p_communication_conversation_id,v_member,v_note_id,'internal_note_added',
    jsonb_build_object('mentionedMembershipIds',v_mentions)
  );

  return jsonb_build_object(
    'ok',true,'contractVersion','communication_conversation_note_v1',
    'identityRoot','communication_conversation',
    'communicationConversationId',p_communication_conversation_id,
    'noteId',v_note_id,'mentionedMembershipIds',v_mentions
  );
end;
$function$;

create or replace function atlas.retract_communication_conversation_note_self_api_v1(
  p_note_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_note atlas.communication_conversation_notes%rowtype;
  v_context jsonb;
  v_member uuid;
begin
  select * into v_note from atlas.communication_conversation_notes where id=p_note_id for update;
  if v_note.id is null then raise exception 'Internal note not found.' using errcode='P0002'; end if;
  v_context:=atlas.communication_conversation_actor_context_self_v1(v_note.communication_conversation_id);
  v_member=(v_context->>'membershipId')::uuid;
  if v_note.author_membership_id is distinct from v_member then
    raise exception 'Only the note author may retract an internal note.' using errcode='42501';
  end if;
  if v_note.note_state='active' then
    update atlas.communication_conversation_notes
    set note_state='retracted',retracted_at=now()
    where id=v_note.id;
    update atlas.communication_conversation_note_mentions
    set mention_state='retracted'
    where note_id=v_note.id and mention_state='active';
    insert into atlas.communication_conversation_activity_events(
      organization_id,communication_conversation_id,actor_membership_id,note_id,event_kind
    ) values (
      v_note.organization_id,v_note.communication_conversation_id,v_member,v_note.id,'internal_note_retracted'
    );
  end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','communication_conversation_note_retract_v1',
    'communicationConversationId',v_note.communication_conversation_id,'noteId',v_note.id,'state','retracted'
  );
end;
$function$;

create or replace function atlas.acknowledge_communication_conversation_mention_self_api_v1(
  p_note_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_mention atlas.communication_conversation_note_mentions%rowtype;
  v_context jsonb;
  v_member uuid;
begin
  select * into v_mention
  from atlas.communication_conversation_note_mentions mention
  where mention.note_id=p_note_id
    and mention.mention_state='active'
    and mention.acknowledged_at is null
    and mention.mentioned_membership_id in (
      select membership.id from atlas.organization_memberships membership
      where membership.user_id=auth.uid() and membership.active
    )
  order by mention.created_at
  limit 1
  for update;

  if v_mention.id is null then
    raise exception 'No unacknowledged mention is available to this Atlas member.' using errcode='P0002';
  end if;
  v_context:=atlas.communication_conversation_actor_context_self_v1(v_mention.communication_conversation_id);
  v_member=(v_context->>'membershipId')::uuid;
  if v_member is distinct from v_mention.mentioned_membership_id then
    raise exception 'Mention belongs to another membership.' using errcode='42501';
  end if;

  update atlas.communication_conversation_note_mentions
  set acknowledged_at=now()
  where id=v_mention.id;

  insert into atlas.communication_conversation_activity_events(
    organization_id,communication_conversation_id,actor_membership_id,target_membership_id,note_id,event_kind
  ) values (
    v_mention.organization_id,v_mention.communication_conversation_id,
    v_member,v_member,v_mention.note_id,'mention_acknowledged'
  );

  return jsonb_build_object(
    'ok',true,'contractVersion','communication_conversation_mention_acknowledge_v1',
    'communicationConversationId',v_mention.communication_conversation_id,
    'noteId',v_mention.note_id,'acknowledged',true
  );
end;
$function$;

create or replace function atlas.schedule_communication_conversation_followup_self_api_v1(
  p_communication_conversation_id uuid,
  p_due_at timestamptz,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_org uuid;
  v_member uuid;
  v_id uuid;
begin
  if p_due_at is null or p_due_at<=now() then
    raise exception 'Follow-up time must be in the future.' using errcode='22023';
  end if;
  v_context:=atlas.communication_conversation_actor_context_self_v1(p_communication_conversation_id);
  v_org=(v_context->>'organizationId')::uuid;
  v_member=(v_context->>'membershipId')::uuid;

  update atlas.communication_conversation_followups
  set followup_state='cancelled',cancelled_at=now(),
      metadata=metadata||jsonb_build_object('supersededByReschedule',true)
  where communication_conversation_id=p_communication_conversation_id
    and membership_id=v_member
    and followup_state='scheduled';

  insert into atlas.communication_conversation_followups(
    organization_id,communication_conversation_id,membership_id,due_at,note,metadata
  ) values (
    v_org,p_communication_conversation_id,v_member,p_due_at,nullif(btrim(coalesce(p_note,'')),''),
    jsonb_build_object('attentionOwner','membership')
  ) returning id into v_id;

  insert into atlas.communication_conversation_activity_events(
    organization_id,communication_conversation_id,actor_membership_id,followup_id,event_kind,metadata
  ) values (
    v_org,p_communication_conversation_id,v_member,v_id,'followup_scheduled',
    jsonb_build_object('dueAt',p_due_at)
  );

  return jsonb_build_object(
    'ok',true,'contractVersion','communication_conversation_followup_v1',
    'identityRoot','communication_conversation',
    'communicationConversationId',p_communication_conversation_id,
    'followupId',v_id,'dueAt',p_due_at,'state','scheduled'
  );
end;
$function$;

create or replace function atlas.resolve_communication_conversation_followup_self_api_v1(
  p_followup_id uuid,
  p_resolution text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_followup atlas.communication_conversation_followups%rowtype;
  v_context jsonb;
  v_member uuid;
  v_resolution text:=lower(btrim(coalesce(p_resolution,'')));
begin
  if v_resolution not in ('completed','cancelled') then
    raise exception 'Follow-up resolution must be completed or cancelled.' using errcode='22023';
  end if;
  select * into v_followup
  from atlas.communication_conversation_followups
  where id=p_followup_id
  for update;
  if v_followup.id is null then raise exception 'Follow-up not found.' using errcode='P0002'; end if;
  v_context:=atlas.communication_conversation_actor_context_self_v1(v_followup.communication_conversation_id);
  v_member=(v_context->>'membershipId')::uuid;
  if v_followup.membership_id is distinct from v_member then
    raise exception 'Follow-up belongs to another Atlas member.' using errcode='42501';
  end if;

  if v_followup.followup_state='scheduled' then
    update atlas.communication_conversation_followups
    set followup_state=v_resolution,
        completed_at=case when v_resolution='completed' then now() else null end,
        cancelled_at=case when v_resolution='cancelled' then now() else null end
    where id=v_followup.id;

    insert into atlas.communication_conversation_activity_events(
      organization_id,communication_conversation_id,actor_membership_id,followup_id,event_kind
    ) values (
      v_followup.organization_id,v_followup.communication_conversation_id,v_member,v_followup.id,
      case when v_resolution='completed' then 'followup_completed' else 'followup_cancelled' end
    );
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','communication_conversation_followup_resolve_v1',
    'communicationConversationId',v_followup.communication_conversation_id,
    'followupId',v_followup.id,'state',v_resolution
  );
end;
$function$;

create or replace function atlas.takeover_communication_email_draft_self_api_v1(
  p_draft_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_draft atlas.communication_email_drafts%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_ref text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_draft from atlas.communication_email_drafts where id=p_draft_id for update;
  if v_draft.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
  if v_draft.draft_state<>'active' then
    raise exception 'Only an active unscheduled draft may be taken over.' using errcode='55000';
  end if;
  select * into v_member
  from atlas.organization_memberships
  where organization_id=v_draft.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_member.id is null
     or not atlas.communication_endpoint_membership_has_capability_v1(
       v_draft.communication_endpoint_id,v_member.id,'send'
     ) then
    raise exception 'Communication Endpoint send authority required.' using errcode='42501';
  end if;

  if v_draft.author_membership_id is distinct from v_member.id then
    for v_ref in select value #>> '{}' from jsonb_array_elements(v_draft.attachment_refs)
    loop
      update atlas.communication_outbound_attachments
      set staged_by_membership_id=v_member.id,updated_at=now()
      where id=v_ref::uuid
        and communication_endpoint_id=v_draft.communication_endpoint_id
        and attachment_state='ready';
    end loop;

    update atlas.communication_email_drafts
    set author_membership_id=v_member.id,
        metadata=metadata||jsonb_build_object(
          'takenOverAt',now(),
          'takeoverReason',nullif(btrim(coalesce(p_reason,'')),'')
        ),
        version=version+1,
        updated_at=now()
    where id=v_draft.id;

    if v_draft.communication_conversation_id is not null then
      insert into atlas.communication_conversation_activity_events(
        organization_id,communication_conversation_id,actor_membership_id,
        target_membership_id,draft_id,event_kind,metadata
      ) values (
        v_draft.organization_id,v_draft.communication_conversation_id,v_member.id,
        v_draft.author_membership_id,v_draft.id,'draft_taken_over',
        jsonb_build_object('reason',nullif(btrim(coalesce(p_reason,'')),''))
      );
    end if;
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','communication_email_draft_takeover_v1',
    'draftId',v_draft.id,'authorMembershipId',v_member.id,
    'communicationConversationId',v_draft.communication_conversation_id
  );
end;
$function$;

create or replace function atlas.organization_correspondence_personal_attention_self_v1(
  p_organization_id uuid default null
)
returns table(
  communication_conversation_id uuid,
  attention_kinds jsonb,
  next_due_at timestamptz,
  mention_count integer
)
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
with authorized as (
  select
    conversation.id as communication_conversation_id,
    atlas.organization_correspondence_effective_organization_v1(conversation.id) as organization_id,
    conversation.subject,
    atlas.current_effective_organization_membership_v1(
      atlas.organization_correspondence_effective_organization_v1(conversation.id)
    ) as viewer_membership_id
  from atlas.communication_conversations conversation
  where auth.uid() is not null
    and conversation.organization_id is not null
    and conversation.principal_id is null
    and atlas.organization_correspondence_read_authorized_self_v1(conversation.id)
    and (
      p_organization_id is null
      or atlas.organization_correspondence_effective_organization_v1(conversation.id)=p_organization_id
    )
),
response_attention as (
  select authorized.communication_conversation_id
  from authorized
  left join lateral (
    select event.speaker_address
    from atlas.communication_conversation_events membership
    join atlas.communication_events event on event.id=membership.communication_event_id
    where membership.communication_conversation_id=authorized.communication_conversation_id
    order by coalesce(membership.occurred_at,event.occurred_at,event.captured_at) desc,
             membership.created_at desc,membership.id desc
    limit 1
  ) latest_event on true
  left join lateral (
    select response.id,response.case_state
    from atlas.institutional_conversation_roots root
    join atlas.institutional_conversation_response_cases response
      on response.institutional_conversation_id=root.institutional_conversation_id
    where root.communication_conversation_id=authorized.communication_conversation_id
    order by (response.case_state<>'closed') desc,response.opened_at desc,response.id desc
    limit 1
  ) response_case on true
  left join lateral (
    select allocation.assignee_membership_id
    from atlas.institutional_conversation_response_work_bindings binding
    join atlas.work_allocations allocation on allocation.work_item_id=binding.work_item_id
    where binding.response_case_id=response_case.id
      and allocation.allocation_role='responsible' and allocation.state='active'
    order by allocation.allocated_at desc,allocation.id desc
    limit 1
  ) responsible on true
  where (
    response_case.case_state in ('needs_response','waiting_internal')
    and responsible.assignee_membership_id=authorized.viewer_membership_id
  ) or (
    (response_case.case_state='unclaimed' or responsible.assignee_membership_id is null)
    and not (
      coalesce(latest_event.speaker_address,'') ~* '(^|[-._+])(no-?reply|automated|automation|dmarc|mailer-daemon|notification|notifications|alerts?|security)([-._+]|@|$)'
      or coalesce(authorized.subject,'') ~* '\\m(confirmation code|verification code|reset your password|password reset|report domain:|report domain|dmarc|account activity:|account alert:|new login|security alert|one[- ]time code|sign[- ]in code)\\M'
    )
  )
),
mention_attention as (
  select mention.communication_conversation_id,count(*)::integer as mention_count
  from atlas.communication_conversation_note_mentions mention
  join atlas.communication_conversation_notes note on note.id=mention.note_id and note.note_state='active'
  join authorized on authorized.communication_conversation_id=mention.communication_conversation_id
  where mention.mention_state='active'
    and mention.acknowledged_at is null
    and mention.mentioned_membership_id=authorized.viewer_membership_id
  group by mention.communication_conversation_id
),
followup_attention as (
  select followup.communication_conversation_id,min(followup.due_at) as next_due_at
  from atlas.communication_conversation_followups followup
  join authorized on authorized.communication_conversation_id=followup.communication_conversation_id
  where followup.followup_state='scheduled'
    and followup.membership_id=authorized.viewer_membership_id
    and followup.due_at<=now()
  group by followup.communication_conversation_id
),
ids as (
  select communication_conversation_id from response_attention
  union
  select communication_conversation_id from mention_attention
  union
  select communication_conversation_id from followup_attention
)
select ids.communication_conversation_id,
       (
         select coalesce(jsonb_agg(kind order by kind),'[]'::jsonb)
         from (
           select 'response'::text as kind where exists(
             select 1 from response_attention r where r.communication_conversation_id=ids.communication_conversation_id
           )
           union all
           select 'mention' where exists(
             select 1 from mention_attention m where m.communication_conversation_id=ids.communication_conversation_id
           )
           union all
           select 'followup' where exists(
             select 1 from followup_attention f where f.communication_conversation_id=ids.communication_conversation_id
           )
         ) kinds
       ) as attention_kinds,
       (select f.next_due_at from followup_attention f where f.communication_conversation_id=ids.communication_conversation_id),
       coalesce((select m.mention_count from mention_attention m where m.communication_conversation_id=ids.communication_conversation_id),0)
from ids;
$function$;

create or replace function atlas.organization_correspondence_attention_summary_self_api_v2(
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select count(*)::integer into v_count
  from atlas.organization_correspondence_personal_attention_self_v1(p_organization_id);
  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_correspondence_attention_summary_v2',
    'identityRoot','communication_conversation',
    'organizationId',p_organization_id,
    'attentionCount',coalesce(v_count,0),
    'countSemantics','unique_common_conversations'
  );
end;
$function$;

create or replace function atlas.organization_correspondence_list_self_api_v3(
  p_organization_id uuid default null,
  p_communication_endpoint_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.organization_correspondence_list_self_api_v2(
    p_organization_id,p_communication_endpoint_id,p_limit
  );

  with attention as (
    select * from atlas.organization_correspondence_personal_attention_self_v1(p_organization_id)
  )
  select coalesce(jsonb_agg(
    item||jsonb_build_object(
      'personalAttention',
      case when attention.communication_conversation_id is null then null else jsonb_build_object(
        'kinds',attention.attention_kinds,
        'nextDueAt',attention.next_due_at,
        'mentionCount',attention.mention_count
      ) end
    )
    order by
      (attention.communication_conversation_id is not null) desc,
      attention.next_due_at nulls last,
      (item->>'lastActivityAt')::timestamptz desc,
      item->>'communicationConversationId'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item
  left join attention on attention.communication_conversation_id=(item->>'communicationConversationId')::uuid;

  return (v_base-'items')||jsonb_build_object(
    'contractVersion','organization_correspondence_list_v3',
    'items',v_items
  );
end;
$function$;

create or replace function atlas.organization_correspondence_conversation_self_api_v5(
  p_communication_conversation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_context jsonb;
  v_org uuid;
  v_viewer uuid;
  v_notes jsonb;
  v_followups jsonb;
  v_drafts jsonb;
  v_activity jsonb;
begin
  v_base:=atlas.organization_correspondence_conversation_self_api_v4(
    p_communication_conversation_id
  );
  if coalesce(v_base->>'identityRoot','')<>'communication_conversation' then
    raise exception 'Common Correspondence detail lost Communication Conversation custody.' using errcode='23514';
  end if;
  v_context:=atlas.communication_conversation_actor_context_self_v1(p_communication_conversation_id);
  v_org=(v_context->>'organizationId')::uuid;
  v_viewer=(v_context->>'membershipId')::uuid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'noteId',note.id,
    'body',note.body,
    'authorMembershipId',note.author_membership_id,
    'authorLabel',coalesce(profile.display_name,membership.role,note.author_membership_id::text),
    'isMine',note.author_membership_id=v_viewer,
    'createdAt',note.created_at,
    'mentions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'membershipId',mention.mentioned_membership_id,
        'label',coalesce(mp.display_name,mm.role,mention.mentioned_membership_id::text),
        'isMe',mention.mentioned_membership_id=v_viewer,
        'acknowledgedAt',mention.acknowledged_at
      ) order by coalesce(mp.display_name,mm.role,mention.mentioned_membership_id::text))
      from atlas.communication_conversation_note_mentions mention
      join atlas.organization_memberships mm on mm.id=mention.mentioned_membership_id
      left join atlas.user_profiles mp on mp.user_id=mm.user_id
      where mention.note_id=note.id and mention.mention_state='active'
    ),'[]'::jsonb)
  ) order by note.created_at,note.id),'[]'::jsonb)
  into v_notes
  from atlas.communication_conversation_notes note
  join atlas.organization_memberships membership on membership.id=note.author_membership_id
  left join atlas.user_profiles profile on profile.user_id=membership.user_id
  where note.communication_conversation_id=p_communication_conversation_id
    and note.note_state='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'followupId',followup.id,
    'dueAt',followup.due_at,
    'note',followup.note,
    'state',followup.followup_state,
    'dueNow',followup.due_at<=now(),
    'createdAt',followup.created_at
  ) order by followup.due_at,followup.id),'[]'::jsonb)
  into v_followups
  from atlas.communication_conversation_followups followup
  where followup.communication_conversation_id=p_communication_conversation_id
    and followup.membership_id=v_viewer
    and followup.followup_state='scheduled';

  select coalesce(jsonb_agg(jsonb_build_object(
    'draftId',draft.id,
    'communicationEndpointId',draft.communication_endpoint_id,
    'authorMembershipId',draft.author_membership_id,
    'authorLabel',coalesce(profile.display_name,membership.role,draft.author_membership_id::text),
    'isMine',draft.author_membership_id=v_viewer,
    'state',draft.draft_state,
    'compositionKind',draft.composition_kind,
    'sourceCommunicationEventId',draft.source_communication_event_id,
    'updatedAt',draft.updated_at,
    'takeoverAllowed',
      draft.author_membership_id<>v_viewer
      and draft.draft_state='active'
      and atlas.communication_endpoint_membership_has_capability_v1(
        draft.communication_endpoint_id,v_viewer,'send'
      )
  ) order by draft.updated_at desc,draft.id),'[]'::jsonb)
  into v_drafts
  from atlas.communication_email_drafts draft
  join atlas.organization_memberships membership on membership.id=draft.author_membership_id
  left join atlas.user_profiles profile on profile.user_id=membership.user_id
  where draft.communication_conversation_id=p_communication_conversation_id
    and draft.draft_state in ('active','scheduled');

  with timeline as (
    select activity.occurred_at,
           activity.id::text as tie,
           activity.event_kind as kind,
           activity.actor_membership_id,
           activity.target_membership_id,
           activity.communication_event_id,
           activity.note_id,
           activity.followup_id,
           activity.draft_id,
           null::uuid as work_item_id,
           null::uuid as outbound_operation_id,
           activity.metadata
    from atlas.communication_conversation_activity_events activity
    where activity.communication_conversation_id=p_communication_conversation_id

    union all

    select response.occurred_at,response.id::text,
           'response_'||response.event_kind,
           response.actor_membership_id,response.target_membership_id,
           response.related_communication_event_id,
           null,null,null,response.work_item_id,null,
           jsonb_strip_nulls(jsonb_build_object(
             'fromState',response.from_state,'toState',response.to_state
           ))
    from atlas.institutional_conversation_roots root
    join atlas.institutional_conversation_response_cases response_case
      on response_case.institutional_conversation_id=root.institutional_conversation_id
    join atlas.institutional_conversation_response_events response
      on response.response_case_id=response_case.id
    where root.communication_conversation_id=p_communication_conversation_id

    union all

    select link.created_at,link.id::text,'work_created',
           null,null,link.communication_event_id,
           null,null,null,link.work_item_id,null,
           jsonb_build_object('evidenceExcerpt',link.evidence_excerpt)
    from atlas.communication_derived_work_links link
    join atlas.institutional_conversation_roots root
      on root.institutional_conversation_id=link.institutional_conversation_id
    where root.communication_conversation_id=p_communication_conversation_id

    union all

    select operation.authorized_at,operation.id::text,
           'outbound_authorized',operation.initiated_by_membership_id,null,
           operation.source_communication_event_id,
           null,null,null,null,operation.id,
           jsonb_build_object(
             'compositionKind',operation.composition_kind,
             'operationState',operation.operation_state
           )
    from atlas.communication_outbound_operations operation
    where operation.communication_conversation_id=p_communication_conversation_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind',timeline.kind,
    'occurredAt',timeline.occurred_at,
    'actorMembershipId',timeline.actor_membership_id,
    'actorLabel',coalesce(actor_profile.display_name,actor.role),
    'targetMembershipId',timeline.target_membership_id,
    'targetLabel',coalesce(target_profile.display_name,target.role),
    'communicationEventId',timeline.communication_event_id,
    'noteId',timeline.note_id,
    'followupId',timeline.followup_id,
    'draftId',timeline.draft_id,
    'workItemId',timeline.work_item_id,
    'outboundOperationId',timeline.outbound_operation_id,
    'metadata',timeline.metadata
  ) order by timeline.occurred_at,timeline.tie),'[]'::jsonb)
  into v_activity
  from timeline
  left join atlas.organization_memberships actor on actor.id=timeline.actor_membership_id
  left join atlas.user_profiles actor_profile on actor_profile.user_id=actor.user_id
  left join atlas.organization_memberships target on target.id=timeline.target_membership_id
  left join atlas.user_profiles target_profile on target_profile.user_id=target.user_id;

  return v_base||jsonb_build_object(
    'contractVersion','organization_correspondence_conversation_v5',
    'internalNotes',v_notes,
    'personalFollowups',v_followups,
    'draftPresence',v_drafts,
    'activityHistory',v_activity
  );
end;
$function$;

revoke all on function atlas.guard_communication_composition_provenance_v1() from public,anon,authenticated;
revoke all on function atlas.reject_communication_conversation_activity_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.bind_communication_outbound_composition_from_draft_v1() from public,anon,authenticated;
grant execute on function atlas.guard_communication_composition_provenance_v1() to service_role;
grant execute on function atlas.reject_communication_conversation_activity_mutation_v1() to service_role;
grant execute on function atlas.bind_communication_outbound_composition_from_draft_v1() to service_role;

revoke all on function atlas.communication_conversation_actor_context_self_v1(uuid) from public,anon;
revoke all on function atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text) from public,anon;
revoke all on function atlas.save_communication_email_draft_self_api_v3(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) from public,anon;
revoke all on function atlas.organization_correspondence_drafts_self_api_v2(uuid,uuid,uuid,integer) from public,anon;
revoke all on function atlas.record_communication_conversation_note_self_api_v1(uuid,text,jsonb) from public,anon;
revoke all on function atlas.retract_communication_conversation_note_self_api_v1(uuid) from public,anon;
revoke all on function atlas.acknowledge_communication_conversation_mention_self_api_v1(uuid) from public,anon;
revoke all on function atlas.schedule_communication_conversation_followup_self_api_v1(uuid,timestamptz,text) from public,anon;
revoke all on function atlas.resolve_communication_conversation_followup_self_api_v1(uuid,text) from public,anon;
revoke all on function atlas.takeover_communication_email_draft_self_api_v1(uuid,text) from public,anon;
revoke all on function atlas.organization_correspondence_personal_attention_self_v1(uuid) from public,anon;
revoke all on function atlas.organization_correspondence_attention_summary_self_api_v2(uuid) from public,anon;
revoke all on function atlas.organization_correspondence_list_self_api_v3(uuid,uuid,integer) from public,anon;
revoke all on function atlas.organization_correspondence_conversation_self_api_v5(uuid) from public,anon;

grant execute on function atlas.communication_conversation_actor_context_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text) to authenticated,service_role;
grant execute on function atlas.save_communication_email_draft_self_api_v3(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_drafts_self_api_v2(uuid,uuid,uuid,integer) to authenticated,service_role;
grant execute on function atlas.record_communication_conversation_note_self_api_v1(uuid,text,jsonb) to authenticated,service_role;
grant execute on function atlas.retract_communication_conversation_note_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.acknowledge_communication_conversation_mention_self_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.schedule_communication_conversation_followup_self_api_v1(uuid,timestamptz,text) to authenticated,service_role;
grant execute on function atlas.resolve_communication_conversation_followup_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function atlas.takeover_communication_email_draft_self_api_v1(uuid,text) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_personal_attention_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_attention_summary_self_api_v2(uuid) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_list_self_api_v3(uuid,uuid,integer) to authenticated,service_role;
grant execute on function atlas.organization_correspondence_conversation_self_api_v5(uuid) to authenticated,service_role;

comment on function atlas.organization_correspondence_recipient_proposal_self_api_v1(uuid,uuid,text) is
'Authority-neutral recipient proposal from one exact Communication Event. Reply All excludes self and BCC; recipients remain editable before authorization.';
comment on function atlas.save_communication_email_draft_self_api_v3(uuid,uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text,text,text,jsonb,uuid,timestamptz,jsonb) is
'Common Conversation draft command with exact source Event provenance for reply, reply_all, and forward. Forward does not masquerade as reply threading.';
comment on table atlas.communication_conversation_notes is
'Internal-only collaboration notes rooted in common Communication Conversation identity; never Communication Events and never externally sendable.';
comment on table atlas.communication_conversation_followups is
'Personal future-attention commitments on common Communication Conversations; distinct from mailbox disposition and response responsibility.';
comment on table atlas.communication_conversation_activity_events is
'Append-only collaboration/consequence activity evidence for common Communication Conversations. Communication Events remain separate immutable external evidence.';

commit;
