-- Atlas Communication Ledger v1 schema proof.
--
-- Executable reviewed source only. This is NOT a canonical migration.
-- The final migration identity must be generated through the governed
-- noel-core-db Supabase migration/release lane.
--
-- Governing order:
-- source -> capture -> custody -> reconciliation -> interpretation -> authorized state
--
-- This tranche implements source registration, relay authentication, and custody only.

create table atlas.communication_relay_credentials (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[0-9a-f]{64}$'),
  label text not null check (btrim(label) <> ''),
  status text not null default 'active' check (status in ('active','revoked')),
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (revoked_at is null or status = 'revoked'),
  check (expires_at is null or expires_at > created_at)
);

create table atlas.communication_threads (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  source_thread_ref text not null check (btrim(source_thread_ref) <> ''),
  first_event_at timestamptz,
  last_event_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connected_source_id, source_thread_ref),
  unique (id, connected_source_id, principal_id)
);

create table atlas.communication_ingest_batches (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  relay_credential_id uuid references atlas.communication_relay_credentials(id) on delete set null,
  capture_mode text not null,
  source_manifest_sha256 text,
  supplied_count integer not null check (supplied_count >= 0),
  admitted_count integer not null default 0 check (admitted_count >= 0),
  already_in_custody_count integer not null default 0 check (already_in_custody_count >= 0),
  conflict_count integer not null default 0 check (conflict_count >= 0),
  first_occurred_at timestamptz,
  last_occurred_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table atlas.communication_events (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  thread_id uuid,
  ingest_batch_id uuid not null references atlas.communication_ingest_batches(id) on delete restrict,
  source_event_ref text not null check (btrim(source_event_ref) <> ''),
  occurred_at timestamptz,
  captured_at timestamptz not null,
  direction text not null check (direction in ('incoming','outgoing','unknown')),
  speaker_is_self boolean not null,
  speaker_address text,
  body text,
  body_state text not null check (body_state in ('exact_text','attributed_body_preserved','empty')),
  source_authority text not null default 'evidence_only' check (source_authority = 'evidence_only'),
  permitted_state_effect text not null default 'append_source_attributed_evidence_only'
    check (permitted_state_effect = 'append_source_attributed_evidence_only'),
  governing_state_changed boolean not null default false check (governing_state_changed = false),
  source_content_hash text not null check (source_content_hash ~ '^[0-9a-f]{64}$'),
  custody_source_hash text not null check (custody_source_hash ~ '^[0-9a-f]{64}$'),
  canonical_event jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (thread_id, connected_source_id, principal_id)
    references atlas.communication_threads(id, connected_source_id, principal_id) on delete restrict,
  unique (connected_source_id, source_event_ref)
);

create table atlas.communication_event_conflicts (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  existing_event_id uuid not null references atlas.communication_events(id) on delete restrict,
  ingest_batch_id uuid not null references atlas.communication_ingest_batches(id) on delete restrict,
  source_event_ref text not null,
  existing_source_content_hash text not null,
  incoming_source_content_hash text not null,
  existing_custody_source_hash text not null,
  incoming_custody_source_hash text not null,
  incoming_event jsonb not null,
  detected_at timestamptz not null default now(),
  unique (existing_event_id, incoming_custody_source_hash)
);

create table atlas.communication_attachments (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  event_id uuid not null references atlas.communication_events(id) on delete restrict,
  source_attachment_ref text not null check (btrim(source_attachment_ref) <> ''),
  mime_type text,
  transfer_name text,
  source_content_hash text,
  custody_locator text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (event_id, source_attachment_ref)
);

create index communication_relay_credentials_source_status_idx
  on atlas.communication_relay_credentials (connected_source_id, status, created_at desc);
create index communication_events_principal_occurred_idx
  on atlas.communication_events (principal_id, occurred_at desc, id);
create index communication_events_thread_occurred_idx
  on atlas.communication_events (thread_id, occurred_at, id) where thread_id is not null;
create index communication_batches_principal_created_idx
  on atlas.communication_ingest_batches (principal_id, created_at desc);
create index communication_conflicts_principal_detected_idx
  on atlas.communication_event_conflicts (principal_id, detected_at desc);

create or replace function atlas.guard_communication_source_principal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal_user_id uuid;
  v_source_user_id uuid;
begin
  select p.user_id into v_principal_user_id
  from atlas.principals p
  where p.id = new.principal_id and p.status = 'active';

  select s.custodian_user_id into v_source_user_id
  from atlas.connected_sources s
  where s.id = new.connected_source_id
    and s.authorization_state <> 'revoked';

  if v_principal_user_id is null or v_source_user_id is null or v_principal_user_id <> v_source_user_id then
    raise exception 'Communication source is outside the Principal custody root.' using errcode = '42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_communication_source_principal_v1() from public, anon, authenticated;
grant execute on function atlas.guard_communication_source_principal_v1() to service_role;

create trigger communication_relay_credentials_source_guard
before insert or update on atlas.communication_relay_credentials
for each row execute function atlas.guard_communication_source_principal_v1();
create trigger communication_threads_source_guard
before insert or update on atlas.communication_threads
for each row execute function atlas.guard_communication_source_principal_v1();
create trigger communication_ingest_batches_source_guard
before insert or update on atlas.communication_ingest_batches
for each row execute function atlas.guard_communication_source_principal_v1();
create trigger communication_events_source_guard
before insert on atlas.communication_events
for each row execute function atlas.guard_communication_source_principal_v1();
create trigger communication_event_conflicts_source_guard
before insert on atlas.communication_event_conflicts
for each row execute function atlas.guard_communication_source_principal_v1();

create or replace function atlas.reject_communication_event_mutation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
begin
  raise exception 'Communication source events are append-only; record later observations separately.';
end;
$function$;

create trigger communication_events_append_only
before update or delete on atlas.communication_events
for each row execute function atlas.reject_communication_event_mutation_v1();

alter table atlas.communication_relay_credentials enable row level security;
alter table atlas.communication_threads enable row level security;
alter table atlas.communication_ingest_batches enable row level security;
alter table atlas.communication_events enable row level security;
alter table atlas.communication_event_conflicts enable row level security;
alter table atlas.communication_attachments enable row level security;

create policy communication_threads_self_read
on atlas.communication_threads for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = communication_threads.principal_id and p.user_id = auth.uid() and p.status = 'active'
));
create policy communication_ingest_batches_self_read
on atlas.communication_ingest_batches for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = communication_ingest_batches.principal_id and p.user_id = auth.uid() and p.status = 'active'
));
create policy communication_events_self_read
on atlas.communication_events for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = communication_events.principal_id and p.user_id = auth.uid() and p.status = 'active'
));
create policy communication_event_conflicts_self_read
on atlas.communication_event_conflicts for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = communication_event_conflicts.principal_id and p.user_id = auth.uid() and p.status = 'active'
));
create policy communication_attachments_self_read
on atlas.communication_attachments for select to authenticated
using (exists (
  select 1 from atlas.communication_events e
  join atlas.principals p on p.id = e.principal_id
  where e.id = communication_attachments.event_id
    and e.principal_id = communication_attachments.principal_id
    and p.user_id = auth.uid() and p.status = 'active'
));

revoke all on atlas.communication_relay_credentials from anon, authenticated;
revoke all on atlas.communication_threads from anon;
revoke all on atlas.communication_ingest_batches from anon;
revoke all on atlas.communication_events from anon;
revoke all on atlas.communication_event_conflicts from anon;
revoke all on atlas.communication_attachments from anon;

grant select on atlas.communication_threads to authenticated;
grant select on atlas.communication_ingest_batches to authenticated;
grant select on atlas.communication_events to authenticated;
grant select on atlas.communication_event_conflicts to authenticated;
grant select on atlas.communication_attachments to authenticated;

create or replace function atlas.register_communication_relay_api_v1(
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_source_id uuid;
  v_credential_id uuid;
  v_provider_key text := lower(nullif(btrim(p_provider_key), ''));
  v_account_key text := nullif(btrim(p_provider_account_key), '');
  v_label text := coalesce(nullif(btrim(p_display_label), ''), 'Apple Messages relay');
  v_token_hash text := lower(nullif(btrim(p_token_hash), ''));
begin
  if v_user_id is null then
    raise exception 'Authentication is required to pair a communication relay.' using errcode = '28000';
  end if;
  if v_provider_key not in ('apple_messages','sms','email','whatsapp','slack','teams','crm_message','call_transcript','manual_capture') then
    raise exception 'Unsupported communication provider.' using errcode = '22023';
  end if;
  if v_account_key is null then
    raise exception 'A provider account key is required.' using errcode = '22023';
  end if;
  if v_token_hash is null or v_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Relay token hash must be a lowercase SHA-256 digest.' using errcode = '22023';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id = v_user_id and p.status = 'active';
  if v_principal_id is null then
    raise exception 'No active Atlas Principal exists for the authenticated user.' using errcode = '42501';
  end if;

  insert into atlas.connected_sources (
    custodian_user_id, provider_key, provider_account_key, display_label,
    authorization_state, capabilities, metadata
  ) values (
    v_user_id, v_provider_key, v_account_key, v_label,
    'connected', jsonb_build_object('communicationCapture', true),
    jsonb_build_object('continuityRelay', true)
  )
  on conflict (custodian_user_id, provider_key, provider_account_key)
    where custodian_user_id is not null
  do update set
    display_label = excluded.display_label,
    authorization_state = 'connected',
    capabilities = atlas.connected_sources.capabilities || excluded.capabilities,
    metadata = atlas.connected_sources.metadata || excluded.metadata,
    revoked_at = null,
    updated_at = now()
  returning id into v_source_id;

  update atlas.communication_relay_credentials
  set status = 'revoked', revoked_at = now()
  where principal_id = v_principal_id
    and connected_source_id = v_source_id
    and status = 'active';

  insert into atlas.communication_relay_credentials (
    principal_id, connected_source_id, token_hash, label
  ) values (
    v_principal_id, v_source_id, v_token_hash, v_label
  ) returning id into v_credential_id;

  return jsonb_build_object(
    'schemaVersion', 'atlas_communication_relay_pairing_v1',
    'connectedSourceId', v_source_id,
    'relayCredentialId', v_credential_id,
    'providerKey', v_provider_key,
    'providerAccountKey', v_account_key,
    'governingStateChanged', false
  );
end;
$function$;

revoke all on function atlas.register_communication_relay_api_v1(text,text,text,text) from public, anon;
grant execute on function atlas.register_communication_relay_api_v1(text,text,text,text) to authenticated, service_role;

create or replace function atlas.ingest_communication_events_relay_api_v1(
  p_relay_token_hash text,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_token_hash text := lower(nullif(btrim(p_relay_token_hash), ''));
  v_principal_id uuid;
  v_source_id uuid;
  v_credential_id uuid;
  v_source_kind text;
  v_source_account_ref text;
  v_capture_mode text;
  v_manifest_sha text;
  v_supplied integer;
  v_admitted integer := 0;
  v_already integer := 0;
  v_conflicts integer := 0;
  v_batch_id uuid;
  v_event jsonb;
  v_event_ref text;
  v_thread_ref text;
  v_thread_id uuid;
  v_occurred_at timestamptz;
  v_captured_at timestamptz;
  v_source_hash text;
  v_custody_hash text;
  v_existing_id uuid;
  v_existing_source_hash text;
  v_existing_custody_hash text;
  v_first_occurred timestamptz;
  v_last_occurred timestamptz;
begin
  if v_token_hash is null or v_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid communication relay credential.' using errcode = '28000';
  end if;

  select c.id, c.principal_id, c.connected_source_id, s.provider_key, s.provider_account_key
    into v_credential_id, v_principal_id, v_source_id, v_source_kind, v_source_account_ref
  from atlas.communication_relay_credentials c
  join atlas.connected_sources s on s.id = c.connected_source_id
  join atlas.principals p on p.id = c.principal_id
  where c.token_hash = v_token_hash
    and c.status = 'active'
    and (c.expires_at is null or c.expires_at > now())
    and s.authorization_state = 'connected'
    and s.custodian_user_id = p.user_id
    and p.status = 'active';

  if v_credential_id is null then
    raise exception 'Invalid or revoked communication relay credential.' using errcode = '28000';
  end if;
  if jsonb_typeof(p_events) <> 'array' then
    raise exception 'p_events must be a JSON array.' using errcode = '22023';
  end if;

  v_supplied := jsonb_array_length(p_events);
  if v_supplied < 1 or v_supplied > 1000 then
    raise exception 'Communication relay batches must contain between 1 and 1000 events.' using errcode = '22023';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_events) e
    where e #>> '{source,kind}' is distinct from v_source_kind
       or e #>> '{source,accountRef}' is distinct from v_source_account_ref
  ) then
    raise exception 'Communication batch source identity does not match the paired relay.' using errcode = '42501';
  end if;

  v_capture_mode := coalesce(nullif(btrim(p_events #>> '{0,captureMode}'), ''), 'live_capture');
  v_manifest_sha := nullif(lower(btrim(p_manifest->>'exportSha256')), '');
  if v_manifest_sha is not null and v_manifest_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'Manifest exportSha256 must be a lowercase SHA-256 digest.' using errcode = '22023';
  end if;

  insert into atlas.communication_ingest_batches (
    principal_id, connected_source_id, relay_credential_id, capture_mode,
    source_manifest_sha256, supplied_count, metadata
  ) values (
    v_principal_id, v_source_id, v_credential_id, v_capture_mode,
    v_manifest_sha, v_supplied, coalesce(p_manifest, '{}'::jsonb)
  ) returning id into v_batch_id;

  for v_event in select value from jsonb_array_elements(p_events)
  loop
    if v_event->>'schemaVersion' is distinct from 'atlas_communication_event_v1'
       or v_event->>'sourceAuthority' is distinct from 'evidence_only'
       or v_event->>'permittedStateEffect' is distinct from 'append_source_attributed_evidence_only'
       or coalesce((v_event->>'governingStateChanged')::boolean, true) <> false then
      raise exception 'Communication event violates the evidence-only canonical contract.' using errcode = '22023';
    end if;
    if v_event->>'direction' not in ('incoming','outgoing','unknown')
       or v_event->>'bodyState' not in ('exact_text','attributed_body_preserved','empty') then
      raise exception 'Communication event contains unsupported state.' using errcode = '22023';
    end if;

    v_event_ref := nullif(btrim(v_event #>> '{source,eventRef}'), '');
    if v_event_ref is null then
      raise exception 'Communication event source.eventRef is required.' using errcode = '22023';
    end if;
    v_source_hash := lower(coalesce(v_event->>'contentHash', ''));
    if v_source_hash !~ '^[0-9a-f]{64}$' then
      raise exception 'Communication event contentHash must be a lowercase SHA-256 digest.' using errcode = '22023';
    end if;

    v_custody_hash := encode(extensions.digest(
      jsonb_build_object(
        'source', v_event->'source',
        'direction', v_event->'direction',
        'speaker', v_event->'speaker',
        'occurredAt', v_event->'occurredAt',
        'body', v_event->'body',
        'bodyState', v_event->'bodyState',
        'sourcePayload', v_event->'sourcePayload'
      )::text,
      'sha256'
    ), 'hex');

    v_occurred_at := case when v_event->>'occurredAt' is null then null else (v_event->>'occurredAt')::timestamptz end;
    v_captured_at := (v_event->>'capturedAt')::timestamptz;
    v_thread_ref := nullif(btrim(v_event #>> '{source,threadRef}'), '');
    v_thread_id := null;

    if v_thread_ref is not null then
      insert into atlas.communication_threads (
        principal_id, connected_source_id, source_thread_ref, first_event_at, last_event_at
      ) values (
        v_principal_id, v_source_id, v_thread_ref, v_occurred_at, v_occurred_at
      )
      on conflict (connected_source_id, source_thread_ref)
      do update set
        first_event_at = case
          when atlas.communication_threads.first_event_at is null then excluded.first_event_at
          when excluded.first_event_at is null then atlas.communication_threads.first_event_at
          else least(atlas.communication_threads.first_event_at, excluded.first_event_at)
        end,
        last_event_at = case
          when atlas.communication_threads.last_event_at is null then excluded.last_event_at
          when excluded.last_event_at is null then atlas.communication_threads.last_event_at
          else greatest(atlas.communication_threads.last_event_at, excluded.last_event_at)
        end,
        updated_at = now()
      returning id into v_thread_id;
    end if;

    v_existing_id := null;
    select e.id, e.source_content_hash, e.custody_source_hash
      into v_existing_id, v_existing_source_hash, v_existing_custody_hash
    from atlas.communication_events e
    where e.connected_source_id = v_source_id and e.source_event_ref = v_event_ref;

    if v_existing_id is not null then
      if v_existing_source_hash = v_source_hash and v_existing_custody_source_hash = v_custody_hash then
        v_already := v_already + 1;
      else
        v_conflicts := v_conflicts + 1;
        insert into atlas.communication_event_conflicts (
          principal_id, connected_source_id, existing_event_id, ingest_batch_id,
          source_event_ref, existing_source_content_hash, incoming_source_content_hash,
          existing_custody_source_hash, incoming_custody_source_hash, incoming_event
        ) values (
          v_principal_id, v_source_id, v_existing_id, v_batch_id,
          v_event_ref, v_existing_source_hash, v_source_hash,
          v_existing_custody_hash, v_custody_hash, v_event
        ) on conflict (existing_event_id, incoming_custody_source_hash) do nothing;
      end if;
      continue;
    end if;

    insert into atlas.communication_events (
      principal_id, connected_source_id, thread_id, ingest_batch_id, source_event_ref,
      occurred_at, captured_at, direction, speaker_is_self, speaker_address,
      body, body_state, source_authority, permitted_state_effect,
      governing_state_changed, source_content_hash, custody_source_hash, canonical_event
    ) values (
      v_principal_id, v_source_id, v_thread_id, v_batch_id, v_event_ref,
      v_occurred_at, v_captured_at, v_event->>'direction',
      coalesce((v_event #>> '{speaker,isSelf}')::boolean, false),
      v_event #>> '{speaker,address}', v_event->>'body', v_event->>'bodyState',
      'evidence_only', 'append_source_attributed_evidence_only', false,
      v_source_hash, v_custody_hash, v_event
    );
    v_admitted := v_admitted + 1;

    if v_occurred_at is not null then
      v_first_occurred := case when v_first_occurred is null then v_occurred_at else least(v_first_occurred, v_occurred_at) end;
      v_last_occurred := case when v_last_occurred is null then v_occurred_at else greatest(v_last_occurred, v_occurred_at) end;
    end if;
  end loop;

  update atlas.communication_ingest_batches
  set admitted_count = v_admitted,
      already_in_custody_count = v_already,
      conflict_count = v_conflicts,
      first_occurred_at = v_first_occurred,
      last_occurred_at = v_last_occurred,
      completed_at = now()
  where id = v_batch_id;

  update atlas.communication_relay_credentials
  set last_used_at = now()
  where id = v_credential_id;

  update atlas.connected_sources
  set last_sync_at = now(),
      metadata = metadata || jsonb_build_object(
        'continuityLastIngestedAt', now(),
        'continuityLastOccurredAt', v_last_occurred,
        'continuityLastBatchId', v_batch_id
      ),
      updated_at = now()
  where id = v_source_id;

  return jsonb_build_object(
    'schemaVersion', 'atlas_communication_ingest_receipt_v1',
    'batchId', v_batch_id,
    'connectedSourceId', v_source_id,
    'sourceKind', v_source_kind,
    'sourceAccountRef', v_source_account_ref,
    'supplied', v_supplied,
    'admitted', v_admitted,
    'alreadyInCustody', v_already,
    'conflicts', v_conflicts,
    'firstOccurredAt', v_first_occurred,
    'lastOccurredAt', v_last_occurred,
    'governingStateChanged', false
  );
end;
$function$;

revoke all on function atlas.ingest_communication_events_relay_api_v1(text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.ingest_communication_events_relay_api_v1(text,jsonb,jsonb) to service_role;

create or replace function atlas.communication_source_health_self_api_v1()
returns table (
  connected_source_id uuid,
  provider_key text,
  provider_account_key text,
  display_label text,
  authorization_state text,
  last_sync_at timestamptz,
  last_custodied_event_at timestamptz,
  event_count bigint,
  conflict_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select
    s.id,
    s.provider_key,
    s.provider_account_key,
    s.display_label,
    s.authorization_state,
    s.last_sync_at,
    max(e.occurred_at),
    count(distinct e.id),
    count(distinct c.id)
  from atlas.connected_sources s
  left join atlas.communication_events e on e.connected_source_id = s.id
  left join atlas.communication_event_conflicts c on c.connected_source_id = s.id
  where auth.uid() is not null
    and s.custodian_user_id = auth.uid()
    and coalesce((s.capabilities->>'communicationCapture')::boolean, false)
  group by s.id, s.provider_key, s.provider_account_key, s.display_label, s.authorization_state, s.last_sync_at
  order by s.created_at, s.id;
$function$;

revoke all on function atlas.communication_source_health_self_api_v1() from public, anon;
grant execute on function atlas.communication_source_health_self_api_v1() to authenticated, service_role;
