-- Mailroom operational completion v1
-- Tightens evidence provenance, scheduled delivery, attachment cleanup, and Sent truth
-- before the held work-mail release is allowed to reach production.

begin;

-- ---------------------------------------------------------------------------
-- Readable-selection evidence may differ from the raw body only by whitespace.
-- Exact raw offsets are retained when they exist; normalized selections remain
-- tied to the exact communication event and excerpt hash without invented offsets.
-- ---------------------------------------------------------------------------

alter table atlas.communication_derived_work_links
  drop constraint if exists communication_derived_work_excerpt_check;

alter table atlas.communication_derived_work_links
  add constraint communication_derived_work_excerpt_check
  check (
    (evidence_excerpt is null and evidence_start is null and evidence_end is null and evidence_sha256 is null)
    or
    (
      evidence_excerpt is not null
      and evidence_sha256 is not null
      and (
        (evidence_start is null and evidence_end is null)
        or
        (evidence_start is not null and evidence_end is not null and evidence_start >= 0 and evidence_end > evidence_start)
      )
    )
  );

create or replace function atlas.create_communication_derived_work_self_api_v1(
  p_institutional_conversation_id uuid,
  p_communication_event_id uuid,
  p_excerpt text,
  p_title text,
  p_instructions text,
  p_assignee_membership_id uuid,
  p_due_at timestamptz,
  p_expected_duration_minutes integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth, extensions
as $$
declare
  v_conv atlas.institutional_conversations%rowtype;
  v_event atlas.communication_events%rowtype;
  v_endpoint_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_assignee atlas.organization_memberships%rowtype;
  v_existing atlas.communication_derived_work_links%rowtype;
  v_work_id uuid := gen_random_uuid();
  v_link_id uuid := gen_random_uuid();
  v_excerpt text := nullif(btrim(coalesce(p_excerpt,'')), '');
  v_body_normalized text;
  v_excerpt_normalized text;
  v_pos integer;
  v_start integer;
  v_end integer;
  v_sha text;
  v_match_kind text;
  v_assignment jsonb;
  v_time_contract_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_title,'')),'') is null or length(btrim(p_title)) > 220 then
    raise exception 'Task title is required and must be 220 characters or fewer.' using errcode='22023';
  end if;
  if length(coalesce(p_instructions,'')) > 6000 then
    raise exception 'Task details must be 6000 characters or fewer.' using errcode='22023';
  end if;
  if v_excerpt is not null and length(v_excerpt) > 3000 then
    raise exception 'Selected evidence must be 3000 characters or fewer.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null or length(btrim(p_idempotency_key)) > 240 then
    raise exception 'A valid idempotency key is required.' using errcode='22023';
  end if;
  if p_expected_duration_minutes is not null and (p_expected_duration_minutes < 0 or p_expected_duration_minutes > 1440) then
    raise exception 'Expected duration must be between 0 and 1440 minutes.' using errcode='22023';
  end if;

  select * into v_conv from atlas.institutional_conversations where id=p_institutional_conversation_id;
  if v_conv.id is null then raise exception 'Institutional conversation not found.' using errcode='P0002'; end if;

  select e.* into v_event
  from atlas.institutional_conversation_messages m
  join atlas.communication_events e on e.id=m.communication_event_id
  where m.institutional_conversation_id=v_conv.id and m.communication_event_id=p_communication_event_id
  limit 1;
  if v_event.id is null then raise exception 'Message does not belong to this conversation.' using errcode='22023'; end if;

  select communication_endpoint_id into v_endpoint_id
  from atlas.institutional_conversation_endpoints
  where institutional_conversation_id=v_conv.id
  order by case endpoint_role when 'primary' then 0 else 1 end,created_at limit 1;

  select * into v_actor from atlas.organization_memberships
  where organization_id=v_conv.organization_id and user_id=auth.uid() and active
  order by created_at limit 1;
  if v_actor.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select * into v_existing from atlas.communication_derived_work_links
  where organization_id=v_conv.organization_id and idempotency_key=btrim(p_idempotency_key) limit 1;
  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','communication_derived_work_create_v1','deduplicated',true,
      'linkId',v_existing.id,'workItemId',v_existing.work_item_id
    );
  end if;

  if v_excerpt is not null then
    v_pos := strpos(coalesce(v_event.body,''),v_excerpt);
    if v_pos > 0 then
      v_start := v_pos - 1;
      v_end := v_start + char_length(v_excerpt);
      v_match_kind := 'exact_raw';
    else
      v_body_normalized := btrim(regexp_replace(coalesce(v_event.body,''),'[[:space:]]+',' ','g'));
      v_excerpt_normalized := btrim(regexp_replace(v_excerpt,'[[:space:]]+',' ','g'));
      if v_excerpt_normalized = '' or strpos(v_body_normalized,v_excerpt_normalized) <= 0 then
        raise exception 'Selected text is not present in the canonical message body.' using errcode='22023';
      end if;
      v_start := null;
      v_end := null;
      v_match_kind := 'normalized_whitespace';
    end if;
    v_sha := encode(extensions.digest(v_event.id::text || ':' || v_excerpt,'sha256'),'hex');
  end if;

  if p_assignee_membership_id is not null then
    select * into v_assignee from atlas.organization_memberships
    where id=p_assignee_membership_id and organization_id=v_conv.organization_id and active;
    if v_assignee.id is null then raise exception 'Choose an active organization member.' using errcode='22023'; end if;
    if not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_assignee.id,'view') then
      raise exception 'The assignee must be authorized to view this communication endpoint.' using errcode='42501';
    end if;
    if v_assignee.id is distinct from v_actor.id
       and not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint_id,v_actor.id,'handoff') then
      raise exception 'Endpoint handoff authority is required to assign communication-derived work to another member.' using errcode='42501';
    end if;
  end if;

  insert into atlas.work_items(
    id,organization_id,organization_unit_id,title,instructions,work_state,
    jurisdiction_key,source_object_type,source_object_id,created_by_user_id,stable_key,metadata
  ) values (
    v_work_id,v_conv.organization_id,v_conv.organization_unit_id,btrim(p_title),nullif(btrim(coalesce(p_instructions,'')),''),'open',
    'communication:endpoint:'||v_endpoint_id::text,'communication_event',v_event.id,auth.uid(),
    'communication-derived-work:'||v_link_id::text,
    jsonb_build_object('contractVersion','communication_derived_work_v1','institutionalConversationId',v_conv.id,'communicationEventId',v_event.id)
  );

  insert into atlas.communication_derived_work_links(
    id,organization_id,institutional_conversation_id,communication_event_id,work_item_id,
    created_by_membership_id,evidence_excerpt,evidence_start,evidence_end,evidence_sha256,idempotency_key,metadata
  ) values (
    v_link_id,v_conv.organization_id,v_conv.id,v_event.id,v_work_id,v_actor.id,
    v_excerpt,v_start,v_end,v_sha,btrim(p_idempotency_key),
    jsonb_strip_nulls(jsonb_build_object('source','mailroom','evidenceMatch',v_match_kind))
  );

  if p_due_at is not null or p_expected_duration_minutes is not null then
    insert into atlas.work_time_contracts(
      organization_id,work_item_id,contract_state,latest_lawful_at,hard_finish_at,
      expected_duration_minutes,movement_policy,consequence_of_delay,source_kind,source_id,source_confidence,metadata
    ) values (
      v_conv.organization_id,v_work_id,'active',p_due_at,p_due_at,p_expected_duration_minutes,
      case when p_due_at is null then 'unplaced' else 'fixed' end,'{}'::jsonb,
      'communication_derived_work',v_link_id,1,
      jsonb_build_object('institutionalConversationId',v_conv.id,'communicationEventId',v_event.id)
    ) returning id into v_time_contract_id;
  end if;

  if v_assignee.id is not null then
    v_assignment := atlas.set_company_work_responsibility_internal_v1(
      v_work_id,v_assignee.id,v_actor.id,'communication_derived_work_assignment',
      jsonb_build_object('source','create_communication_derived_work_self_api_v1','derivedWorkLinkId',v_link_id)
    );
  end if;

  return jsonb_build_object(
    'contractVersion','communication_derived_work_create_v1','deduplicated',false,
    'linkId',v_link_id,'workItemId',v_work_id,'conversationId',v_conv.id,'communicationEventId',v_event.id,
    'title',btrim(p_title),'responsibleMembershipId',v_assignee.id,'timeContractId',v_time_contract_id,
    'assignment',v_assignment,
    'evidence',case when v_excerpt is null then null else jsonb_strip_nulls(jsonb_build_object(
      'excerpt',v_excerpt,'start',v_start,'end',v_end,'sha256',v_sha,'match',v_match_kind
    )) end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Draft attachment ownership and cleanup.
-- ---------------------------------------------------------------------------

create or replace function atlas.save_communication_email_draft_self_api_v1(
  p_draft_id uuid,p_communication_endpoint_id uuid,p_institutional_conversation_id uuid,p_reply_to_communication_event_id uuid,
  p_to_recipients jsonb,p_cc_recipients jsonb,p_bcc_recipients jsonb,p_subject text,p_body_text text,p_body_html text,
  p_attachment_refs jsonb,p_signature_id uuid,p_send_after timestamptz,p_metadata jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_id uuid:=coalesce(p_draft_id,gen_random_uuid());
  v_state text;
  v_row atlas.communication_email_drafts%rowtype;
  v_ref text;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null or v_endpoint.endpoint_kind<>'email' then raise exception 'Active email endpoint required.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'send') then raise exception 'Communication endpoint send authority required.' using errcode='42501'; end if;
  if jsonb_typeof(coalesce(p_to_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_cc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_bcc_recipients,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_attachment_refs,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Draft recipients, attachments, and metadata must be valid JSON containers.' using errcode='22023'; end if;
  if p_institutional_conversation_id is not null and not exists(select 1 from atlas.institutional_conversation_endpoints ce where ce.institutional_conversation_id=p_institutional_conversation_id and ce.communication_endpoint_id=v_endpoint.id) then raise exception 'Draft conversation is not associated with this endpoint.' using errcode='42501'; end if;
  if p_reply_to_communication_event_id is not null and (p_institutional_conversation_id is null or not exists(select 1 from atlas.institutional_conversation_messages m where m.institutional_conversation_id=p_institutional_conversation_id and m.communication_event_id=p_reply_to_communication_event_id)) then raise exception 'Reply target must belong to the draft conversation.' using errcode='22023'; end if;
  if p_signature_id is not null and not exists(select 1 from atlas.communication_email_signatures s where s.id=p_signature_id and s.communication_endpoint_id=v_endpoint.id and s.active and (s.owner_membership_id is null or s.owner_membership_id=v_member.id)) then raise exception 'Signature is not available to this sender.' using errcode='22023'; end if;

  for v_ref in select value #>> '{}' from jsonb_array_elements(coalesce(p_attachment_refs,'[]'::jsonb)) loop
    if v_ref !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'Draft attachment reference is not a valid identifier.' using errcode='22023';
    end if;
    if not exists(
      select 1 from atlas.communication_outbound_attachments a
      where a.id=v_ref::uuid
        and a.communication_endpoint_id=v_endpoint.id
        and a.staged_by_membership_id=v_member.id
        and a.attachment_state='ready'
    ) then
      raise exception 'Every draft attachment must be ready, belong to this endpoint, and be staged by the draft author.' using errcode='42501';
    end if;
  end loop;

  v_state:=case when p_send_after is not null and p_send_after>now() then 'scheduled' else 'active' end;
  if p_draft_id is not null then
    select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
    if v_row.id is null or v_row.author_membership_id<>v_member.id then raise exception 'Draft not found for this author.' using errcode='P0002'; end if;
    if v_row.draft_state in ('discarded','authorized') then raise exception 'Finalized draft cannot be edited.' using errcode='55000'; end if;
  end if;

  insert into atlas.communication_email_drafts(
    id,organization_id,organization_unit_id,communication_endpoint_id,institutional_conversation_id,
    reply_to_communication_event_id,author_membership_id,to_recipients,cc_recipients,bcc_recipients,
    subject,body_text,body_html,attachment_refs,signature_id,send_after,draft_state,metadata
  ) values (
    v_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,v_endpoint.id,p_institutional_conversation_id,
    p_reply_to_communication_event_id,v_member.id,coalesce(p_to_recipients,'[]'::jsonb),coalesce(p_cc_recipients,'[]'::jsonb),coalesce(p_bcc_recipients,'[]'::jsonb),
    nullif(p_subject,''),p_body_text,p_body_html,coalesce(p_attachment_refs,'[]'::jsonb),p_signature_id,p_send_after,v_state,coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict(id) do update set
    institutional_conversation_id=excluded.institutional_conversation_id,
    reply_to_communication_event_id=excluded.reply_to_communication_event_id,
    to_recipients=excluded.to_recipients,cc_recipients=excluded.cc_recipients,bcc_recipients=excluded.bcc_recipients,
    subject=excluded.subject,body_text=excluded.body_text,body_html=excluded.body_html,
    attachment_refs=excluded.attachment_refs,signature_id=excluded.signature_id,send_after=excluded.send_after,
    draft_state=excluded.draft_state,metadata=excluded.metadata,version=atlas.communication_email_drafts.version+1,updated_at=now()
  returning * into v_row;

  return jsonb_build_object('contractVersion','communication_email_draft_v2','draftId',v_row.id,'state',v_row.draft_state,'version',v_row.version,'updatedAt',v_row.updated_at,'sendAfter',v_row.send_after);
end;
$$;

create or replace function atlas.detach_communication_email_draft_attachment_self_api_v1(
  p_draft_id uuid,
  p_attachment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_attachment atlas.communication_outbound_attachments%rowtype;
  v_refs jsonb;
  v_revoked boolean:=false;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
  if v_row.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where id=v_row.author_membership_id and user_id=auth.uid() and active;
  if v_member.id is null then raise exception 'Only the draft author may change its attachments.' using errcode='42501'; end if;
  if v_row.draft_state in ('discarded','authorized') then raise exception 'Finalized draft attachments cannot be changed.' using errcode='55000'; end if;

  select coalesce(jsonb_agg(value),'[]'::jsonb) into v_refs
  from jsonb_array_elements(v_row.attachment_refs) item(value)
  where item.value #>> '{}' <> p_attachment_id::text;

  update atlas.communication_email_drafts
  set attachment_refs=v_refs,version=version+1,updated_at=now()
  where id=v_row.id;

  select * into v_attachment from atlas.communication_outbound_attachments where id=p_attachment_id for update;
  if v_attachment.id is not null
     and v_attachment.communication_endpoint_id=v_row.communication_endpoint_id
     and v_attachment.staged_by_membership_id=v_member.id
     and not exists(
       select 1 from atlas.communication_email_drafts d
       where d.id<>v_row.id and d.draft_state in ('active','scheduled') and d.attachment_refs ? p_attachment_id::text
     )
     and not exists(
       select 1 from atlas.communication_outbound_operations o where o.attachment_refs ? p_attachment_id::text
     ) then
    update atlas.communication_outbound_attachments
    set attachment_state='revoked',revoked_at=coalesce(revoked_at,now()),updated_at=now()
    where id=p_attachment_id and attachment_state in ('staging','ready')
    returning * into v_attachment;
    v_revoked:=v_attachment.attachment_state='revoked';
  end if;

  return jsonb_build_object(
    'contractVersion','communication_email_draft_attachment_detach_v1',
    'draftId',v_row.id,'attachmentId',p_attachment_id,'revoked',v_revoked,
    'storageBucket',case when v_revoked then v_attachment.storage_bucket else null end,
    'storageObjectPath',case when v_revoked then v_attachment.storage_object_path else null end
  );
end;
$$;

create or replace function atlas.discard_communication_email_draft_self_api_v1(p_draft_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_ref text;
  v_attachment atlas.communication_outbound_attachments%rowtype;
  v_revoked jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_row from atlas.communication_email_drafts where id=p_draft_id for update;
  if v_row.id is null then raise exception 'Draft not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where id=v_row.author_membership_id and user_id=auth.uid() and active;
  if v_member.id is null then raise exception 'Only the draft author may discard it.' using errcode='42501'; end if;
  if v_row.draft_state='authorized' then raise exception 'Authorized draft cannot be discarded.' using errcode='55000'; end if;

  update atlas.communication_email_drafts set draft_state='discarded',send_after=null,updated_at=now() where id=v_row.id;

  for v_ref in select value #>> '{}' from jsonb_array_elements(v_row.attachment_refs) loop
    select * into v_attachment from atlas.communication_outbound_attachments where id=v_ref::uuid for update;
    if v_attachment.id is not null
       and v_attachment.staged_by_membership_id=v_member.id
       and not exists(
         select 1 from atlas.communication_email_drafts d
         where d.id<>v_row.id and d.draft_state in ('active','scheduled') and d.attachment_refs ? v_ref
       )
       and not exists(select 1 from atlas.communication_outbound_operations o where o.attachment_refs ? v_ref) then
      update atlas.communication_outbound_attachments
      set attachment_state='revoked',revoked_at=coalesce(revoked_at,now()),updated_at=now()
      where id=v_attachment.id and attachment_state in ('staging','ready')
      returning * into v_attachment;
      if v_attachment.attachment_state='revoked' then
        v_revoked:=v_revoked||jsonb_build_array(jsonb_build_object(
          'attachmentId',v_attachment.id,'storageBucket',v_attachment.storage_bucket,'storageObjectPath',v_attachment.storage_object_path
        ));
      end if;
    end if;
  end loop;

  return jsonb_build_object('contractVersion','communication_email_draft_discard_v2','draftId',v_row.id,'state','discarded','revokedAttachments',v_revoked);
end;
$$;

-- ---------------------------------------------------------------------------
-- Scheduled drafts are released only when a real send transport is available.
-- Missing transport is not an error; the draft remains scheduled.
-- ---------------------------------------------------------------------------

create or replace function atlas.release_due_communication_email_drafts_service_v1(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_row atlas.communication_email_drafts%rowtype;
  v_signature atlas.communication_email_signatures%rowtype;
  v_body text;
  v_result jsonb;
  v_released integer:=0;
  v_failed integer:=0;
begin
  if p_limit<1 or p_limit>500 then raise exception 'Limit must be between 1 and 500.' using errcode='22023'; end if;

  for v_row in
    select d.*
    from atlas.communication_email_drafts d
    where d.draft_state='scheduled'
      and d.send_after<=now()
      and exists(
        select 1
        from atlas.communication_endpoint_source_bindings b
        join atlas.connected_sources s on s.id=b.connected_source_id
        where b.communication_endpoint_id=d.communication_endpoint_id
          and b.binding_state='active'
          and b.binding_role in ('send','send_receive')
          and s.authorization_state='connected'
          and s.capabilities @> '{"communicationSend":true}'::jsonb
      )
    order by d.send_after,d.id
    for update skip locked
    limit p_limit
  loop
    begin
      v_body:=coalesce(v_row.body_text,'');
      if v_row.signature_id is not null then
        select * into v_signature from atlas.communication_email_signatures where id=v_row.signature_id and active;
        if v_signature.id is not null and btrim(v_signature.body_text)<>'' then
          v_body:=rtrim(v_body)||E'\n\n'||v_signature.body_text;
        end if;
      end if;

      v_result:=atlas.prepare_institutional_email_send_internal_v2(
        v_row.author_membership_id,v_row.communication_endpoint_id,v_row.institutional_conversation_id,
        v_row.to_recipients,v_row.cc_recipients,v_row.bcc_recipients,v_row.subject,v_body,v_row.body_html,
        v_row.attachment_refs,v_row.reply_to_communication_event_id,'draft:'||v_row.id::text,'scheduled_draft_release'
      );

      update atlas.communication_email_drafts
      set draft_state='authorized',send_after=null,
          authorized_outbound_operation_id=(v_result->>'outboundOperationId')::uuid,
          metadata=(metadata-'lastScheduleError')-'lastScheduleAttemptAt',updated_at=now()
      where id=v_row.id;
      v_released:=v_released+1;
    exception when others then
      update atlas.communication_email_drafts
      set metadata=metadata||jsonb_build_object('lastScheduleError',sqlerrm,'lastScheduleAttemptAt',now()),updated_at=now()
      where id=v_row.id;
      v_failed:=v_failed+1;
    end;
  end loop;

  return jsonb_build_object('contractVersion','communication_email_draft_release_v2','released',v_released,'failed',v_failed);
end;
$$;
revoke all on function atlas.release_due_communication_email_drafts_service_v1(integer) from public,anon,authenticated;

select cron.schedule(
  'atlas-release-due-communication-email-drafts-v1',
  '* * * * *',
  'select atlas.release_due_communication_email_drafts_service_v1(50);'
);

create or replace function atlas.communication_email_drafts_self_v1(
  p_communication_endpoint_id uuid,
  p_institutional_conversation_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_endpoint.id is null or v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then raise exception 'Communication endpoint view authority required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'draftId',d.id,'conversationId',d.institutional_conversation_id,'replyToCommunicationEventId',d.reply_to_communication_event_id,
    'authorMembershipId',d.author_membership_id,'authorLabel',coalesce(up.display_name,u.email,d.author_membership_id::text),
    'isMine',d.author_membership_id=v_member.id,
    'to',case when d.author_membership_id=v_member.id then d.to_recipients else '[]'::jsonb end,
    'cc',case when d.author_membership_id=v_member.id then d.cc_recipients else '[]'::jsonb end,
    'bcc',case when d.author_membership_id=v_member.id then d.bcc_recipients else '[]'::jsonb end,
    'subject',d.subject,'bodyText',case when d.author_membership_id=v_member.id then d.body_text else null end,
    'attachmentRefs',case when d.author_membership_id=v_member.id then d.attachment_refs else '[]'::jsonb end,
    'signatureId',case when d.author_membership_id=v_member.id then d.signature_id else null end,
    'sendAfter',d.send_after,'state',d.draft_state,'version',d.version,'updatedAt',d.updated_at,
    'scheduleError',case when d.author_membership_id=v_member.id then nullif(d.metadata->>'lastScheduleError','') else null end,
    'lastScheduleAttemptAt',case when d.author_membership_id=v_member.id then d.metadata->>'lastScheduleAttemptAt' else null end
  ) order by d.updated_at desc),'[]'::jsonb) into v_items
  from atlas.communication_email_drafts d
  join atlas.organization_memberships om on om.id=d.author_membership_id
  left join auth.users u on u.id=om.user_id
  left join atlas.user_profiles up on up.user_id=om.user_id
  where d.communication_endpoint_id=v_endpoint.id
    and d.draft_state in ('active','scheduled')
    and (p_institutional_conversation_id is null or d.institutional_conversation_id=p_institutional_conversation_id);

  return jsonb_build_object('contractVersion','communication_email_drafts_v2','items',v_items);
end;
$$;

-- ---------------------------------------------------------------------------
-- Sent is an outbound-message projection, not "thread whose latest item is ours".
-- ---------------------------------------------------------------------------

create or replace function atlas.institutional_sent_mail_self_v1(
  p_communication_endpoint_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>500 then raise exception 'Sent limit must be between 1 and 500.' using errcode='22023'; end if;
  select * into v_endpoint from atlas.communication_endpoints where id=p_communication_endpoint_id and endpoint_state='active';
  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='P0002'; end if;
  select * into v_member from atlas.organization_memberships where organization_id=v_endpoint.organization_id and user_id=auth.uid() and active order by created_at limit 1;
  if v_member.id is null or not atlas.communication_endpoint_membership_has_capability_v1(v_endpoint.id,v_member.id,'view') then
    raise exception 'Communication endpoint view authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'outboundOperationId',q.id,'conversationId',q.institutional_conversation_id,'communicationEventId',q.communication_event_id,
    'operationState',q.operation_state,'authorizedAt',q.authorized_at,'acceptedAt',q.accepted_at,'failedAt',q.failed_at,
    'to',q.to_recipients,'cc',q.cc_recipients,'bcc',q.bcc_recipients,
    'subject',q.subject,'bodyText',q.body_text,'attachmentRefs',q.attachment_refs,
    'latestAttempt',q.latest_attempt,'recipientResults',q.recipient_results
  ) order by q.authorized_at desc,q.id),'[]'::jsonb) into v_items
  from (
    select o.*,el.communication_event_id,
      la.attempt as latest_attempt,coalesce(la.recipients,'[]'::jsonb) as recipient_results
    from atlas.communication_outbound_operations o
    left join atlas.communication_outbound_event_links el on el.outbound_operation_id=o.id
    left join lateral (
      select jsonb_build_object(
        'attemptId',a.id,'attemptNumber',a.attempt_number,'resultState',a.result_state,
        'providerMessageRef',a.provider_message_ref,'attemptedAt',a.attempted_at
      ) as attempt,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'role',r.recipient_role,'address',r.recipient_address,'resultState',r.result_state,'providerResponse',r.provider_response
      ) order by r.recipient_role,r.recipient_address),'[]'::jsonb)
       from atlas.communication_outbound_attempt_recipients r where r.outbound_attempt_id=a.id) as recipients
      from atlas.communication_outbound_attempts a
      where a.outbound_operation_id=o.id
      order by a.attempt_number desc limit 1
    ) la on true
    where o.communication_endpoint_id=v_endpoint.id
    order by o.authorized_at desc,o.id
    limit p_limit
  ) q;

  return jsonb_build_object('contractVersion','institutional_sent_mail_v1','communicationEndpointId',v_endpoint.id,'items',v_items);
end;
$$;

-- ---------------------------------------------------------------------------
-- Browser membranes for the completion contracts.
-- ---------------------------------------------------------------------------

create or replace function public.detach_communication_email_draft_attachment_self_api_v1(p_draft_id uuid,p_attachment_id uuid)
returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$
  select atlas.detach_communication_email_draft_attachment_self_api_v1($1,$2);
$$;

create or replace function public.institutional_sent_mail_self_v1(p_communication_endpoint_id uuid,p_limit integer default 200)
returns jsonb language sql security invoker set search_path=pg_catalog,public,atlas as $$
  select atlas.institutional_sent_mail_self_v1($1,$2);
$$;

revoke all on function public.detach_communication_email_draft_attachment_self_api_v1(uuid,uuid) from public,anon;
grant execute on function public.detach_communication_email_draft_attachment_self_api_v1(uuid,uuid) to authenticated,service_role;
revoke all on function public.institutional_sent_mail_self_v1(uuid,integer) from public,anon;
grant execute on function public.institutional_sent_mail_self_v1(uuid,integer) to authenticated,service_role;

grant execute on function atlas.detach_communication_email_draft_attachment_self_api_v1(uuid,uuid) to authenticated,service_role;
grant execute on function atlas.institutional_sent_mail_self_v1(uuid,integer) to authenticated,service_role;

commit;
