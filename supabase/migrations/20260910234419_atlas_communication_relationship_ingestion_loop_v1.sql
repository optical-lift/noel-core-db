begin;

create table atlas.communication_participant_relationship_resolutions (
  id uuid primary key default gen_random_uuid(),
  communication_event_participant_id uuid not null references atlas.communication_event_participants(id) on delete restrict,
  communication_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  resolution_state text not null check (resolution_state in ('linked','already_linked','identity_review_required','no_match','no_relationship_in_scope','relationship_inactive','relationship_role_inactive','identifier_conflict','identity_link_conflict','unsupported_identifier','private_source_requires_explicit_share')),
  external_relationship_id uuid references atlas.external_relationships(id) on delete restrict,
  communication_identity_link_id uuid references atlas.communication_identity_links(id) on delete restrict,
  identity_source_record_id uuid references atlas.identity_source_records(id) on delete restrict,
  identity_review_id uuid references atlas.identity_reconciliation_reviews(id) on delete restrict,
  resolution_sha256 text not null check (resolution_sha256 ~ '^[0-9a-f]{64}$'),
  resolution_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_payload)='object'),
  created_at timestamptz not null default now(),
  unique(communication_event_participant_id,resolution_sha256)
);
create index communication_participant_resolution_event_idx on atlas.communication_participant_relationship_resolutions(communication_event_id,created_at,id);
create index communication_participant_resolution_relationship_idx on atlas.communication_participant_relationship_resolutions(external_relationship_id,created_at desc,id) where external_relationship_id is not null;
comment on table atlas.communication_participant_relationship_resolutions is 'Append-only accounting of attempts to resolve source-observed communication participants to organization External Relationships. Unresolved, ambiguous, private-source, and conflict states remain explicit; no communication evidence creates a customer merely by being received.';

create or replace function atlas.prevent_communication_participant_resolution_mutation_v1()
returns trigger language plpgsql set search_path=pg_catalog,atlas as $function$
begin raise exception 'Communication participant resolution history is append-only.' using errcode='55000'; end;$function$;
create trigger communication_participant_relationship_resolutions_append_only_v1 before update or delete on atlas.communication_participant_relationship_resolutions for each row execute function atlas.prevent_communication_participant_resolution_mutation_v1();

create or replace function atlas.link_communication_identity_to_external_relationship_service_v2(
  p_connected_source_id uuid,
  p_external_relationship_id uuid,
  p_source_identity_kind text,
  p_source_identity_key text,
  p_thread_id uuid default null,
  p_principal_id uuid default null,
  p_relation_basis text default 'exact_external_identifier',
  p_confidence numeric default 1,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_relationship atlas.external_relationships%rowtype;
  v_principal_user_id uuid;
  v_kind text:=lower(btrim(coalesce(p_source_identity_kind,'')));
  v_key text;
  v_existing atlas.communication_identity_links%rowtype;
  v_label text;
  v_link_id uuid;
begin
  if v_kind='' or btrim(coalesce(p_source_identity_key,''))='' then raise exception 'Communication source identity kind/key are required.' using errcode='22023'; end if;
  if p_confidence is not null and (p_confidence<0 or p_confidence>1) then raise exception 'Confidence must be between 0 and 1.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_provenance,'{}'::jsonb))<>'object' then raise exception 'Provenance must be an object.' using errcode='22023'; end if;
  v_key:=case when v_kind in ('email','phone') then atlas.normalize_external_party_identifier_v1(v_kind,p_source_identity_key) else btrim(p_source_identity_key) end;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Connected communication source is required.' using errcode='P0002'; end if;
  select * into v_relationship from atlas.external_relationships where id=p_external_relationship_id;
  if v_relationship.id is null then raise exception 'External relationship not found.' using errcode='P0002'; end if;

  if v_source.custodian_user_id is not null then
    if p_principal_id is null then raise exception 'Person-owned source requires Principal custody.' using errcode='42501'; end if;
    select user_id into v_principal_user_id from atlas.principals where id=p_principal_id and status='active';
    if v_principal_user_id is null or v_principal_user_id is distinct from v_source.custodian_user_id then raise exception 'Principal does not own the communication source.' using errcode='42501'; end if;
    if not exists(select 1 from atlas.organization_memberships om where om.organization_id=v_relationship.organization_id and om.user_id=v_principal_user_id and om.active) then raise exception 'Principal is not a member of the target relationship organization.' using errcode='42501'; end if;
  else
    if p_principal_id is not null then raise exception 'Organization-owned source must not be linked through Principal custody.' using errcode='42501'; end if;
    if v_relationship.organization_id is distinct from v_source.custodian_organization_id or v_relationship.organization_unit_id is distinct from v_source.custodian_organization_unit_id then raise exception 'External relationship is outside the organization communication source scope.' using errcode='42501'; end if;
  end if;

  if p_thread_id is not null and not exists(
    select 1 from atlas.communication_threads t where t.id=p_thread_id and t.connected_source_id=v_source.id
      and t.principal_id is not distinct from p_principal_id
      and t.organization_id is not distinct from v_source.custodian_organization_id
      and t.organization_unit_id is not distinct from v_source.custodian_organization_unit_id
  ) then raise exception 'Thread is outside communication source custody.' using errcode='23514'; end if;

  if not exists(select 1 from atlas.identity_subject_external_identifiers i where i.organization_id=v_relationship.organization_id and i.subject_id=v_relationship.subject_id and i.identifier_type=v_kind and i.identifier_normalized=v_key and i.is_current) then
    raise exception 'Communication source identity is not an established identifier for the relationship subject.' using errcode='23514';
  end if;

  select * into v_existing from atlas.communication_identity_links l where l.connected_source_id=v_source.id and l.source_identity_kind=v_kind and l.source_identity_key=v_key and l.relation_status='active' limit 1;
  if v_existing.id is not null then
    if v_existing.target_domain='atlas' and v_existing.target_kind='external_relationship' and v_existing.target_id=v_relationship.id::text then
      return jsonb_build_object('contractVersion','link_communication_identity_to_external_relationship_service_v2','state','already_linked','communicationIdentityLinkId',v_existing.id,'created',false);
    end if;
    return jsonb_build_object('contractVersion','link_communication_identity_to_external_relationship_service_v2','state','identity_link_conflict','communicationIdentityLinkId',v_existing.id,'existingTargetDomain',v_existing.target_domain,'existingTargetKind',v_existing.target_kind,'existingTargetId',v_existing.target_id,'requestedExternalRelationshipId',v_relationship.id,'created',false);
  end if;

  select display_name into v_label from atlas.identity_subject_projections where subject_id=v_relationship.subject_id;
  insert into atlas.communication_identity_links(principal_id,organization_id,organization_unit_id,connected_source_id,thread_id,source_identity_kind,source_identity_key,target_domain,target_kind,target_id,target_label,relation_basis,confidence,relation_status,provenance,created_by_user_id)
  values(p_principal_id,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,p_thread_id,v_kind,v_key,'atlas','external_relationship',v_relationship.id::text,v_label,lower(btrim(coalesce(nullif(p_relation_basis,''),'exact_external_identifier'))),p_confidence,'active',coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('organizationId',v_relationship.organization_id,'identitySubjectId',v_relationship.subject_id,'sourceCustody',case when v_source.custodian_organization_id is null then 'principal' else 'organization' end),null)
  returning id into v_link_id;
  return jsonb_build_object('contractVersion','link_communication_identity_to_external_relationship_service_v2','state','linked','communicationIdentityLinkId',v_link_id,'created',true);
end;$function$;
comment on function atlas.link_communication_identity_to_external_relationship_service_v2(uuid,uuid,text,text,uuid,uuid,text,numeric,jsonb) is 'Creates a source-identity to External Relationship bridge only when the address/identifier is already established on that relationship subject. Organization-owned sources may link only inside their source organization/unit; person-owned sources retain explicit Principal/member sharing custody.';

create or replace function atlas.reconcile_communication_event_external_relationships_service_v1(p_communication_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_participant atlas.communication_event_participants%rowtype;
  v_resolution jsonb;
  v_link jsonb;
  v_state text;
  v_record_state text;
  v_relationship_id uuid;
  v_source_record_id uuid;
  v_review_id uuid;
  v_link_id uuid;
  v_payload jsonb;
  v_hash text;
  v_linked integer:=0;
  v_unresolved integer:=0;
  v_skipped integer:=0;
begin
  select * into v_event from atlas.communication_events where id=p_communication_event_id;
  if v_event.id is null then raise exception 'Communication event not found.' using errcode='P0002'; end if;
  select * into v_source from atlas.connected_sources where id=v_event.connected_source_id;
  if v_source.id is null then raise exception 'Communication source not found.' using errcode='P0002'; end if;

  for v_participant in select * from atlas.communication_event_participants p where p.communication_event_id=v_event.id order by p.created_at,p.id loop
    if v_participant.is_self then continue; end if;
    v_relationship_id:=null; v_source_record_id:=null; v_review_id:=null; v_link_id:=null;

    if v_source.custodian_organization_id is null then
      v_record_state:='private_source_requires_explicit_share';
      v_payload:=jsonb_build_object('reason','Person-owned communication evidence is not automatically admitted to any organization relationship.','participantId',v_participant.id,'principalId',v_event.principal_id);
      v_skipped:=v_skipped+1;
    elsif v_participant.address_kind not in ('email','phone') then
      v_record_state:='unsupported_identifier';
      v_payload:=jsonb_build_object('reason','Only established email/phone identity coordinates auto-resolve from organization communication sources.','participantId',v_participant.id,'addressKind',v_participant.address_kind);
      v_skipped:=v_skipped+1;
    else
      v_resolution:=atlas.resolve_external_relationship_service_v1(
        p_organization_id=>v_source.custodian_organization_id,
        p_organization_unit_id=>v_source.custodian_organization_unit_id,
        p_role_key=>'customer',
        p_display_name=>nullif(btrim(v_participant.metadata->>'displayName'),''),
        p_subject_kind=>'unknown',
        p_identifiers=>jsonb_build_array(jsonb_build_object('type',v_participant.address_kind,'value',v_participant.address,'normalized',v_participant.address_normalized,'identityScoped',true)),
        p_source_system_key=>'communication:'||v_source.provider_key,
        p_source_record_kind=>'participant',
        p_source_record_key=>'event:'||v_event.source_event_ref||':participant:'||v_participant.participant_role||':'||v_participant.address_kind||':'||v_participant.address_normalized,
        p_source_observed_at=>v_event.occurred_at,
        p_source_authority=>'evidence_only',
        p_custody_ref=>jsonb_build_object('connectedSourceId',v_source.id,'communicationEventId',v_event.id,'participantId',v_participant.id,'sourceEventRef',v_event.source_event_ref),
        p_basis=>jsonb_build_object('communicationDirection',v_event.direction,'participantRole',v_participant.participant_role,'addressKind',v_participant.address_kind),
        p_allow_create=>false,
        p_new_relationship_state=>'prospective'
      );
      v_state:=v_resolution->>'state';
      begin v_relationship_id:=nullif(v_resolution->>'externalRelationshipId','')::uuid; exception when invalid_text_representation then v_relationship_id:=null; end;
      begin v_source_record_id:=nullif(v_resolution->>'sourceRecordId','')::uuid; exception when invalid_text_representation then v_source_record_id:=null; end;
      begin v_review_id:=nullif(v_resolution->>'reviewId','')::uuid; exception when invalid_text_representation then v_review_id:=null; end;

      if v_state in ('resolved','matched_relationship_without_role') and v_relationship_id is not null then
        v_link:=atlas.link_communication_identity_to_external_relationship_service_v2(v_source.id,v_relationship_id,v_participant.address_kind,v_participant.address,null,null,'canonical_external_party_resolver',1,jsonb_build_object('communicationEventId',v_event.id,'participantId',v_participant.id,'identitySourceRecordId',v_source_record_id));
        begin v_link_id:=nullif(v_link->>'communicationIdentityLinkId','')::uuid; exception when invalid_text_representation then v_link_id:=null; end;
        if v_link->>'state'='linked' then v_record_state:='linked'; v_linked:=v_linked+1;
        elsif v_link->>'state'='already_linked' then v_record_state:='already_linked'; v_linked:=v_linked+1;
        else v_record_state:='identity_link_conflict'; v_unresolved:=v_unresolved+1; end if;
        v_payload:=jsonb_build_object('resolver',v_resolution,'link',v_link);
      else
        v_record_state:=case v_state
          when 'identity_review_required' then 'identity_review_required'
          when 'no_match' then 'no_match'
          when 'matched_subject_no_relationship' then 'no_relationship_in_scope'
          when 'relationship_inactive' then 'relationship_inactive'
          when 'relationship_role_inactive' then 'relationship_role_inactive'
          when 'resolved_with_identifier_conflict' then 'identifier_conflict'
          else 'no_match' end;
        v_payload:=jsonb_build_object('resolver',v_resolution);
        v_unresolved:=v_unresolved+1;
      end if;
    end if;

    v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('state',v_record_state,'externalRelationshipId',v_relationship_id,'communicationIdentityLinkId',v_link_id,'identitySourceRecordId',v_source_record_id,'identityReviewId',v_review_id,'payload',v_payload)::text,'UTF8'),'sha256'),'hex');
    insert into atlas.communication_participant_relationship_resolutions(communication_event_participant_id,communication_event_id,connected_source_id,resolution_state,external_relationship_id,communication_identity_link_id,identity_source_record_id,identity_review_id,resolution_sha256,resolution_payload)
    values(v_participant.id,v_event.id,v_source.id,v_record_state,v_relationship_id,v_link_id,v_source_record_id,v_review_id,v_hash,v_payload)
    on conflict (communication_event_participant_id,resolution_sha256) do nothing;
  end loop;

  return jsonb_build_object('contractVersion','reconcile_communication_event_external_relationships_service_v1','communicationEventId',v_event.id,'sourceCustody',case when v_source.custodian_organization_id is null then 'principal' else 'organization' end,'linkedParticipants',v_linked,'unresolvedParticipants',v_unresolved,'skippedParticipants',v_skipped);
end;$function$;
comment on function atlas.reconcile_communication_event_external_relationships_service_v1(uuid) is 'Reconciles non-self communication participants. Organization-owned sources auto-link only already-known exact/adjudicated external identities and never create a new relationship. Person-owned sources are not automatically shared into organizations.';

create or replace function atlas.ingest_organization_communication_events_service_v1(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_capture_mode text;
  v_manifest_sha text;
  v_supplied integer;
  v_admitted integer:=0;
  v_already integer:=0;
  v_source_state_observations integer:=0;
  v_conflicts integer:=0;
  v_participants_inserted integer:=0;
  v_relationship_links integer:=0;
  v_relationship_unresolved integer:=0;
  v_batch_id uuid;
  v_event jsonb;
  v_event_ref text;
  v_thread_ref text;
  v_thread_id uuid;
  v_event_id uuid;
  v_occurred_at timestamptz;
  v_captured_at timestamptz;
  v_source_hash text;
  v_custody_hash text;
  v_existing atlas.communication_events%rowtype;
  v_observation_id uuid;
  v_first_occurred timestamptz;
  v_last_occurred timestamptz;
  v_participant_result jsonb;
  v_resolution_result jsonb;
  v_participants jsonb;
  v_attachments jsonb;
  v_attachment jsonb;
  v_attachment_ref text;
  v_legacy_participant text;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and custodian_organization_id is not null and authorization_state='connected';
  if v_source.id is null then raise exception 'A connected organization-owned communication source is required.' using errcode='42501'; end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then raise exception 'Connected source is not authorized for communication capture.' using errcode='42501'; end if;
  if jsonb_typeof(p_events)<>'array' then raise exception 'p_events must be a JSON array.' using errcode='22023'; end if;
  v_supplied:=jsonb_array_length(p_events);
  if v_supplied<1 or v_supplied>1000 then raise exception 'Communication batches must contain between 1 and 1000 events.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_manifest,'{}'::jsonb))<>'object' then raise exception 'Manifest must be a JSON object.' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements(p_events) e where e#>>'{source,kind}' is distinct from v_source.provider_key or e#>>'{source,accountRef}' is distinct from v_source.provider_account_key) then raise exception 'Communication batch source identity does not match the connected source.' using errcode='42501'; end if;
  v_capture_mode:=coalesce(nullif(btrim(p_events#>>'{0,captureMode}'),''),'provider_sync');
  v_manifest_sha:=nullif(lower(btrim(p_manifest->>'exportSha256')),'');
  if v_manifest_sha is not null and v_manifest_sha !~ '^[0-9a-f]{64}$' then raise exception 'Manifest exportSha256 must be a lowercase SHA-256 digest.' using errcode='22023'; end if;

  insert into atlas.communication_ingest_batches(principal_id,organization_id,organization_unit_id,connected_source_id,relay_credential_id,capture_mode,source_manifest_sha256,supplied_count,metadata)
  values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,null,v_capture_mode,v_manifest_sha,v_supplied,coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object('ingestContract','organization_communication_ingestion_v1')) returning id into v_batch_id;

  for v_event in select value from jsonb_array_elements(p_events) loop
    if v_event->>'schemaVersion' is distinct from 'atlas_communication_event_v1' or v_event->>'sourceAuthority' is distinct from 'evidence_only' or v_event->>'permittedStateEffect' is distinct from 'append_source_attributed_evidence_only' or coalesce((v_event->>'governingStateChanged')::boolean,true)<>false then raise exception 'Communication event violates the evidence-only canonical contract.' using errcode='22023'; end if;
    if v_event->>'direction' not in ('incoming','outgoing','unknown') or v_event->>'bodyState' not in ('exact_text','attributed_body_preserved','empty') then raise exception 'Communication event contains unsupported state.' using errcode='22023'; end if;
    v_event_ref:=nullif(btrim(v_event#>>'{source,eventRef}'),''); if v_event_ref is null then raise exception 'Communication event source.eventRef is required.' using errcode='22023'; end if;
    v_source_hash:=lower(coalesce(v_event->>'contentHash','')); if v_source_hash !~ '^[0-9a-f]{64}$' then raise exception 'Communication event contentHash must be a lowercase SHA-256 digest.' using errcode='22023'; end if;
    v_occurred_at:=case when v_event->>'occurredAt' is null then null else (v_event->>'occurredAt')::timestamptz end;
    v_captured_at:=coalesce((v_event->>'capturedAt')::timestamptz,now());
    v_thread_ref:=nullif(btrim(v_event#>>'{source,threadRef}'),'');
    v_participants:=coalesce(v_event->'participants','[]'::jsonb);
    if jsonb_typeof(v_participants)<>'array' then raise exception 'canonical participants must be an array.' using errcode='22023'; end if;
    if v_source.provider_key in ('gmail','email','google_gmail') and jsonb_array_length(v_participants)=0 then raise exception 'Email communication ingestion requires canonical sender/recipient participants.' using errcode='22023'; end if;
    v_attachments:=coalesce(v_event->'attachments','[]'::jsonb); if jsonb_typeof(v_attachments)<>'array' then raise exception 'canonical attachments must be an array.' using errcode='22023'; end if;
    v_custody_hash:=encode(extensions.digest(convert_to(jsonb_build_object('source',v_event->'source','direction',v_event->'direction','speaker',v_event->'speaker','occurredAt',v_event->'occurredAt','body',v_event->'body','bodyState',v_event->'bodyState','participants',v_participants,'attachments',v_attachments,'sourcePayload',v_event->'sourcePayload')::text,'UTF8'),'sha256'),'hex');
    v_thread_id:=null;
    if v_thread_ref is not null then
      insert into atlas.communication_threads(principal_id,organization_id,organization_unit_id,connected_source_id,source_thread_ref,first_event_at,last_event_at)
      values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,v_thread_ref,v_occurred_at,v_occurred_at)
      on conflict (connected_source_id,source_thread_ref) do update set first_event_at=case when atlas.communication_threads.first_event_at is null then excluded.first_event_at when excluded.first_event_at is null then atlas.communication_threads.first_event_at else least(atlas.communication_threads.first_event_at,excluded.first_event_at) end,last_event_at=case when atlas.communication_threads.last_event_at is null then excluded.last_event_at when excluded.last_event_at is null then atlas.communication_threads.last_event_at else greatest(atlas.communication_threads.last_event_at,excluded.last_event_at) end,updated_at=now()
      returning id into v_thread_id;
    end if;

    select * into v_existing from atlas.communication_events e where e.connected_source_id=v_source.id and e.source_event_ref=v_event_ref;
    if v_existing.id is not null then
      v_event_id:=v_existing.id;
      if v_existing.source_content_hash=v_source_hash then
        v_already:=v_already+1;
        if v_existing.custody_source_hash is distinct from v_custody_hash then
          v_observation_id:=null;
          insert into atlas.communication_event_source_observations(principal_id,organization_id,organization_unit_id,connected_source_id,event_id,ingest_batch_id,source_event_ref,source_content_hash,custody_source_hash,observation_kind,observed_event,observed_at)
          values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,v_existing.id,v_batch_id,v_event_ref,v_source_hash,v_custody_hash,'source_state_enrichment',v_event,v_captured_at)
          on conflict (event_id,custody_source_hash) do nothing returning id into v_observation_id;
          if v_observation_id is not null then v_source_state_observations:=v_source_state_observations+1; end if;
        end if;
      else
        v_conflicts:=v_conflicts+1;
        insert into atlas.communication_event_conflicts(principal_id,organization_id,organization_unit_id,connected_source_id,existing_event_id,ingest_batch_id,source_event_ref,existing_source_content_hash,incoming_source_content_hash,existing_custody_source_hash,incoming_custody_source_hash,incoming_event)
        values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,v_existing.id,v_batch_id,v_event_ref,v_existing.source_content_hash,v_source_hash,v_existing.custody_source_hash,v_custody_hash,v_event)
        on conflict (existing_event_id,incoming_custody_source_hash) do nothing;
        continue;
      end if;
    else
      insert into atlas.communication_events(principal_id,organization_id,organization_unit_id,connected_source_id,thread_id,ingest_batch_id,source_event_ref,occurred_at,captured_at,direction,speaker_is_self,speaker_address,body,body_state,source_authority,permitted_state_effect,governing_state_changed,source_content_hash,custody_source_hash,canonical_event)
      values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_source.id,v_thread_id,v_batch_id,v_event_ref,v_occurred_at,v_captured_at,v_event->>'direction',coalesce((v_event#>>'{speaker,isSelf}')::boolean,false),v_event#>>'{speaker,address}',v_event->>'body',v_event->>'bodyState','evidence_only','append_source_attributed_evidence_only',false,v_source_hash,v_custody_hash,v_event)
      returning id into v_event_id;
      v_admitted:=v_admitted+1;
    end if;

    if not exists(select 1 from atlas.communication_event_participants p where p.communication_event_id=v_event_id) then
      if jsonb_array_length(v_participants)>0 then
        v_participant_result:=atlas.record_communication_event_participants_service_v1(v_event_id,v_participants);
      else
        v_participants:='[]'::jsonb;
        if nullif(btrim(v_event#>>'{speaker,address}'),'') is not null then v_participants:=v_participants||jsonb_build_array(jsonb_build_object('role','sender','address',v_event#>>'{speaker,address}','isSelf',coalesce((v_event#>>'{speaker,isSelf}')::boolean,false))); end if;
        for v_legacy_participant in select nullif(btrim(x),'') from regexp_split_to_table(coalesce(v_event#>>'{sourcePayload,participantAddresses}',''),'[;,]') x loop if v_legacy_participant is not null then v_participants:=v_participants||jsonb_build_array(jsonb_build_object('role','participant','address',v_legacy_participant,'isSelf',false)); end if; end loop;
        v_participant_result:=atlas.record_communication_event_participants_service_v1(v_event_id,v_participants);
      end if;
      v_participants_inserted:=v_participants_inserted+coalesce((v_participant_result->>'participantsInserted')::int,0);
    end if;

    for v_attachment in select value from jsonb_array_elements(v_attachments) loop
      v_attachment_ref:=nullif(btrim(v_attachment->>'sourceAttachmentRef'),''); if v_attachment_ref is null then raise exception 'Every communication attachment requires sourceAttachmentRef.' using errcode='22023'; end if;
      insert into atlas.communication_attachments(principal_id,organization_id,organization_unit_id,event_id,source_attachment_ref,mime_type,transfer_name,source_content_hash,custody_locator,metadata)
      values(null,v_source.custodian_organization_id,v_source.custodian_organization_unit_id,v_event_id,v_attachment_ref,nullif(lower(btrim(v_attachment->>'mimeType')),''),nullif(btrim(v_attachment->>'transferName'),''),nullif(lower(btrim(v_attachment->>'sourceContentHash')),''),nullif(btrim(v_attachment->>'custodyLocator'),''),coalesce(v_attachment->'metadata','{}'::jsonb))
      on conflict (event_id,source_attachment_ref) do nothing;
    end loop;

    v_resolution_result:=atlas.reconcile_communication_event_external_relationships_service_v1(v_event_id);
    v_relationship_links:=v_relationship_links+coalesce((v_resolution_result->>'linkedParticipants')::int,0);
    v_relationship_unresolved:=v_relationship_unresolved+coalesce((v_resolution_result->>'unresolvedParticipants')::int,0);

    if v_occurred_at is not null then v_first_occurred:=case when v_first_occurred is null then v_occurred_at else least(v_first_occurred,v_occurred_at) end; v_last_occurred:=case when v_last_occurred is null then v_occurred_at else greatest(v_last_occurred,v_occurred_at) end; end if;
  end loop;

  update atlas.communication_ingest_batches set admitted_count=v_admitted,already_in_custody_count=v_already,source_state_observation_count=v_source_state_observations,conflict_count=v_conflicts,first_occurred_at=v_first_occurred,last_occurred_at=v_last_occurred,metadata=metadata||jsonb_build_object('participantsInserted',v_participants_inserted,'relationshipLinks',v_relationship_links,'relationshipUnresolved',v_relationship_unresolved),completed_at=now() where id=v_batch_id;
  update atlas.connected_sources set last_sync_at=now(),metadata=metadata||jsonb_build_object('communicationLastBatchId',v_batch_id,'communicationLastIngestedAt',now(),'communicationLastOccurredAt',v_last_occurred),updated_at=now() where id=v_source.id;

  return jsonb_build_object('contractVersion','organization_communication_ingest_receipt_v1','batchId',v_batch_id,'connectedSourceId',v_source.id,'organizationId',v_source.custodian_organization_id,'organizationUnitId',v_source.custodian_organization_unit_id,'sourceKind',v_source.provider_key,'sourceAccountRef',v_source.provider_account_key,'supplied',v_supplied,'admitted',v_admitted,'alreadyInCustody',v_already,'sourceStateObservations',v_source_state_observations,'conflicts',v_conflicts,'participantsInserted',v_participants_inserted,'relationshipLinks',v_relationship_links,'relationshipUnresolved',v_relationship_unresolved,'firstOccurredAt',v_first_occurred,'lastOccurredAt',v_last_occurred,'governingStateChanged',false);
end;$function$;
comment on function atlas.ingest_organization_communication_events_service_v1(uuid,jsonb,jsonb) is 'Provider-neutral organization mailbox/message ingestion seam. It preserves immutable communication evidence, normalizes canonical participants/attachments, and reconciles known external relationships without creating new customers or changing commercial/work state. Provider OAuth/fetch transport is upstream.';

create or replace view atlas.v_external_relationship_communication_events_v1
with (security_invoker=true)
as
select distinct on (rel.id,e.id)
  rel.organization_id,rel.organization_unit_id,rel.id as external_relationship_id,rel.subject_id,
  e.id as communication_event_id,e.thread_id,e.connected_source_id,e.source_event_ref,e.occurred_at,e.direction,
  coalesce(nullif(e.canonical_event#>>'{source,kind}',''),'communication') as channel,
  coalesce(nullif(e.canonical_event->>'subject',''),nullif(e.canonical_event#>>'{sourcePayload,subject}','')) as subject,
  e.body,p.participant_role,p.address_kind,p.address as participant_address,p.address_normalized,
  e.principal_id as source_principal_id,e.organization_id as source_organization_id,e.organization_unit_id as source_organization_unit_id,
  jsonb_build_object('communicationIdentityLinkId',l.id,'communicationParticipantId',p.id,'sourceAuthority',e.source_authority,'bodyState',e.body_state) as metadata
from atlas.communication_events e
join atlas.communication_event_participants p on p.communication_event_id=e.id and not p.is_self
join atlas.communication_identity_links l on l.connected_source_id=p.connected_source_id and l.source_identity_kind=p.address_kind and l.source_identity_key=p.address_normalized and l.relation_status='active' and l.target_domain='atlas' and l.target_kind='external_relationship'
join atlas.external_relationships rel on rel.id::text=l.target_id
where ((e.direction='incoming' and p.participant_role='sender') or (e.direction='outgoing' and p.participant_role in ('to','cc','bcc','participant')) or e.direction='unknown')
  and ((e.principal_id is not null and l.principal_id=e.principal_id) or (e.organization_id is not null and l.organization_id=e.organization_id and l.organization_unit_id is not distinct from e.organization_unit_id))
order by rel.id,e.id,case p.participant_role when 'sender' then 0 when 'to' then 1 when 'cc' then 2 when 'bcc' then 3 else 4 end,p.id;
comment on view atlas.v_external_relationship_communication_events_v1 is 'Universal correspondence evidence mapped to External Relationships only through explicit active source-identity links. Organization-owned sources may produce links automatically from canonical exact identity resolution; person-owned sources require explicit sharing.';

create or replace view atlas.v_external_relationship_correspondence_position_v1
with (security_invoker=true)
as
select rel.organization_id,rel.organization_unit_id,rel.id as external_relationship_id,rel.subject_id,coalesce(p.display_name,rel.stable_key) as relationship_label,rel.relationship_state,
  lm.occurred_at as last_message_at,lm.direction as last_message_direction,lm.channel as last_message_channel,lm.subject as last_message_subject,lm.body as last_message_body,lm.participant_address as last_message_address,
  lo.occurred_at as last_outgoing_at,lo.subject as last_outgoing_subject,lo.body as last_outgoing_body,
  li.occurred_at as last_incoming_at,li.subject as last_incoming_subject,li.body as last_incoming_body,
  lm.occurred_at as last_contact_at,
  case when lm.direction='outgoing' and (li.occurred_at is null or lm.occurred_at>li.occurred_at) then true else false end as awaiting_reply
from atlas.external_relationships rel
left join atlas.identity_subject_projections p on p.subject_id=rel.subject_id
left join lateral (select e.* from atlas.v_external_relationship_communication_events_v1 e where e.external_relationship_id=rel.id order by e.occurred_at desc nulls last,e.communication_event_id desc limit 1) lm on true
left join lateral (select e.* from atlas.v_external_relationship_communication_events_v1 e where e.external_relationship_id=rel.id and e.direction='outgoing' order by e.occurred_at desc nulls last,e.communication_event_id desc limit 1) lo on true
left join lateral (select e.* from atlas.v_external_relationship_communication_events_v1 e where e.external_relationship_id=rel.id and e.direction='incoming' order by e.occurred_at desc nulls last,e.communication_event_id desc limit 1) li on true
where lm.communication_event_id is not null;

create or replace function atlas.external_relationship_correspondence_history_self_v1(p_organization_id uuid,p_external_relationship_id uuid,p_limit integer default 200)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_items jsonb;
begin
  if auth.uid() is null or not atlas.is_organization_member(p_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  if p_limit<1 or p_limit>1000 then raise exception 'Limit must be between 1 and 1000.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.external_relationships r where r.id=p_external_relationship_id and r.organization_id=p_organization_id) then raise exception 'External relationship is outside organization.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at,x.communication_event_id),'[]'::jsonb) into v_items from (select * from atlas.v_external_relationship_communication_events_v1 e where e.organization_id=p_organization_id and e.external_relationship_id=p_external_relationship_id order by e.occurred_at desc nulls last,e.communication_event_id desc limit p_limit) x;
  return jsonb_build_object('contractVersion','external_relationship_correspondence_history_self_v1','organizationId',p_organization_id,'externalRelationshipId',p_external_relationship_id,'items',v_items);
end;$function$;

create or replace function atlas.external_relationship_correspondence_position_self_v1(p_organization_id uuid,p_organization_unit_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_items jsonb;
begin
  if auth.uid() is null or not atlas.is_organization_member(p_organization_id) then raise exception 'Organization membership required.' using errcode='42501'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units ou where ou.id=p_organization_unit_id and ou.organization_id=p_organization_id) then raise exception 'Organization unit is outside organization.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(to_jsonb(v) order by v.last_contact_at desc nulls last,v.relationship_label),'[]'::jsonb) into v_items from atlas.v_external_relationship_correspondence_position_v1 v where v.organization_id=p_organization_id and (p_organization_unit_id is null or v.organization_unit_id is not distinct from p_organization_unit_id);
  return jsonb_build_object('contractVersion','external_relationship_correspondence_position_self_v1','organizationId',p_organization_id,'organizationUnitId',p_organization_unit_id,'items',v_items);
end;$function$;

alter table atlas.communication_participant_relationship_resolutions enable row level security;
revoke all on table atlas.communication_participant_relationship_resolutions from public,anon,authenticated;
grant all on table atlas.communication_participant_relationship_resolutions to service_role;
revoke all on table atlas.v_external_relationship_communication_events_v1 from public,anon,authenticated;
revoke all on table atlas.v_external_relationship_correspondence_position_v1 from public,anon,authenticated;
grant select on table atlas.v_external_relationship_communication_events_v1 to service_role;
grant select on table atlas.v_external_relationship_correspondence_position_v1 to service_role;

revoke all on function atlas.prevent_communication_participant_resolution_mutation_v1() from public,anon,authenticated;
revoke all on function atlas.link_communication_identity_to_external_relationship_service_v2(uuid,uuid,text,text,uuid,uuid,text,numeric,jsonb) from public,anon,authenticated;
revoke all on function atlas.reconcile_communication_event_external_relationships_service_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.ingest_organization_communication_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
revoke all on function atlas.external_relationship_correspondence_history_self_v1(uuid,uuid,integer) from public,anon,authenticated;
revoke all on function atlas.external_relationship_correspondence_position_self_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function atlas.prevent_communication_participant_resolution_mutation_v1() to service_role;
grant execute on function atlas.link_communication_identity_to_external_relationship_service_v2(uuid,uuid,text,text,uuid,uuid,text,numeric,jsonb) to service_role;
grant execute on function atlas.reconcile_communication_event_external_relationships_service_v1(uuid) to service_role;
grant execute on function atlas.ingest_organization_communication_events_service_v1(uuid,jsonb,jsonb) to service_role;
grant execute on function atlas.external_relationship_correspondence_history_self_v1(uuid,uuid,integer) to authenticated,service_role;
grant execute on function atlas.external_relationship_correspondence_position_self_v1(uuid,uuid) to authenticated,service_role;

commit;
