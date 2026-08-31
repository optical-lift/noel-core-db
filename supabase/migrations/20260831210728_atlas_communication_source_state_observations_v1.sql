BEGIN;

-- Atlas Continuity source-state observations v1.
--
-- Apple Messages mutates delivery/read lifecycle fields after a message is
-- originally written. Those later source observations do not change the
-- exporter contentHash, but they do change the full custody hash. Treating that
-- expected source enrichment as a contradiction creates false conflicts.
--
-- Preserve the first admitted communication event as immutable evidence. When
-- the same source event and contentHash are observed later with a different
-- custody hash, preserve the later source state in its own append-only
-- observation row. Only a changed contentHash for the same source event remains
-- a conflict/revision candidate.

create table atlas.communication_event_source_observations (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  event_id uuid not null references atlas.communication_events(id) on delete restrict,
  ingest_batch_id uuid not null references atlas.communication_ingest_batches(id) on delete restrict,
  source_event_ref text not null check (btrim(source_event_ref) <> ''),
  source_content_hash text not null check (source_content_hash ~ '^[0-9a-f]{64}$'),
  custody_source_hash text not null check (custody_source_hash ~ '^[0-9a-f]{64}$'),
  observation_kind text not null default 'source_state_enrichment'
    check (observation_kind = 'source_state_enrichment'),
  observed_event jsonb not null,
  observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (event_id, custody_source_hash)
);

alter table atlas.communication_ingest_batches
  add column source_state_observation_count integer not null default 0
  check (source_state_observation_count >= 0);

create index communication_event_source_observations_event_idx
  on atlas.communication_event_source_observations (event_id, observed_at, id);
create index communication_event_source_observations_principal_idx
  on atlas.communication_event_source_observations (principal_id, observed_at desc, id);

create or replace function atlas.guard_communication_event_source_observation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_event_principal_id uuid;
  v_event_source_id uuid;
  v_event_ref text;
begin
  select e.principal_id, e.connected_source_id, e.source_event_ref
    into v_event_principal_id, v_event_source_id, v_event_ref
  from atlas.communication_events e
  where e.id = new.event_id;

  if v_event_principal_id is null
     or v_event_principal_id is distinct from new.principal_id
     or v_event_source_id is distinct from new.connected_source_id
     or v_event_ref is distinct from new.source_event_ref then
    raise exception 'Communication source observation does not match its parent event.' using errcode = '42501';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_communication_event_source_observation_v1() from public, anon, authenticated;
grant execute on function atlas.guard_communication_event_source_observation_v1() to service_role;

create trigger communication_event_source_observations_source_guard
before insert on atlas.communication_event_source_observations
for each row execute function atlas.guard_communication_source_principal_v1();

create trigger communication_event_source_observations_parent_guard
before insert on atlas.communication_event_source_observations
for each row execute function atlas.guard_communication_event_source_observation_v1();

create trigger communication_event_source_observations_append_only
before update or delete on atlas.communication_event_source_observations
for each row execute function atlas.reject_communication_event_mutation_v1();

alter table atlas.communication_event_source_observations enable row level security;

create policy communication_event_source_observations_self_read
on atlas.communication_event_source_observations for select to authenticated
using (exists (
  select 1 from atlas.principals p
  where p.id = communication_event_source_observations.principal_id
    and p.user_id = auth.uid()
    and p.status = 'active'
));

revoke all on atlas.communication_event_source_observations from anon;
grant select on atlas.communication_event_source_observations to authenticated;

-- Reclassify any already-recorded false conflicts where semantic source content
-- is identical and only the full source-state custody hash changed.
insert into atlas.communication_event_source_observations (
  principal_id,
  connected_source_id,
  event_id,
  ingest_batch_id,
  source_event_ref,
  source_content_hash,
  custody_source_hash,
  observation_kind,
  observed_event,
  observed_at
)
select
  c.principal_id,
  c.connected_source_id,
  c.existing_event_id,
  c.ingest_batch_id,
  c.source_event_ref,
  c.incoming_source_content_hash,
  c.incoming_custody_source_hash,
  'source_state_enrichment',
  c.incoming_event,
  coalesce(nullif(c.incoming_event->>'capturedAt','')::timestamptz, c.detected_at)
from atlas.communication_event_conflicts c
where c.existing_source_content_hash = c.incoming_source_content_hash
on conflict (event_id, custody_source_hash) do nothing;

update atlas.communication_ingest_batches b
set source_state_observation_count = b.source_state_observation_count + x.observation_count,
    conflict_count = greatest(0, b.conflict_count - x.observation_count)
from (
  select c.ingest_batch_id, count(*)::integer as observation_count
  from atlas.communication_event_conflicts c
  where c.existing_source_content_hash = c.incoming_source_content_hash
  group by c.ingest_batch_id
) x
where b.id = x.ingest_batch_id;

delete from atlas.communication_event_conflicts c
where c.existing_source_content_hash = c.incoming_source_content_hash;

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
  v_source_state_observations integer := 0;
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
  v_observation_id uuid;
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
      if v_existing_source_hash = v_source_hash then
        v_already := v_already + 1;

        if v_existing_custody_hash is distinct from v_custody_hash then
          v_observation_id := null;
          insert into atlas.communication_event_source_observations (
            principal_id,
            connected_source_id,
            event_id,
            ingest_batch_id,
            source_event_ref,
            source_content_hash,
            custody_source_hash,
            observation_kind,
            observed_event,
            observed_at
          ) values (
            v_principal_id,
            v_source_id,
            v_existing_id,
            v_batch_id,
            v_event_ref,
            v_source_hash,
            v_custody_hash,
            'source_state_enrichment',
            v_event,
            v_captured_at
          )
          on conflict (event_id, custody_source_hash) do nothing
          returning id into v_observation_id;

          if v_observation_id is not null then
            v_source_state_observations := v_source_state_observations + 1;
          end if;
        end if;
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
      source_state_observation_count = v_source_state_observations,
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
    'sourceStateObservations', v_source_state_observations,
    'conflicts', v_conflicts,
    'firstOccurredAt', v_first_occurred,
    'lastOccurredAt', v_last_occurred,
    'governingStateChanged', false
  );
end;
$function$;

revoke all on function atlas.ingest_communication_events_relay_api_v1(text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.ingest_communication_events_relay_api_v1(text,jsonb,jsonb) to service_role;

do $assert$
declare
  v_definition text;
  v_false_conflicts bigint;
begin
  select pg_get_functiondef(
    'atlas.ingest_communication_events_relay_api_v1(text,jsonb,jsonb)'::regprocedure
  ) into v_definition;

  if v_definition !~ 'v_existing_source_hash\s*=\s*v_source_hash' then
    raise exception 'Communication source-state observation migration failed: semantic replay branch is absent.';
  end if;

  if v_definition !~ 'communication_event_source_observations' then
    raise exception 'Communication source-state observation migration failed: source-state custody insert is absent.';
  end if;

  select count(*) into v_false_conflicts
  from atlas.communication_event_conflicts
  where existing_source_content_hash = incoming_source_content_hash;

  if v_false_conflicts <> 0 then
    raise exception 'Communication source-state observation migration failed: false lifecycle conflicts remain.';
  end if;
end;
$assert$;

COMMIT;
