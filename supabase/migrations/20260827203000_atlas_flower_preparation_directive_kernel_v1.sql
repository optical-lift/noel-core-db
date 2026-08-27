-- Atlas flower preparation directive kernel v1
--
-- Purpose:
--   Preserve the Owner's governed post-harvest instruction separately from both
--   harvested field truth and the worker's later finished Ready result.
--
-- Truth boundaries:
--   harvest observation -> what was harvested
--   preparation directive -> what Owner asked to be made
--   flower preparation / Ready inventory -> what was actually made
--
-- This migration is intentionally dormant with respect to harvest task creation
-- and application UI. Runtime wiring belongs in a later Atlas application cut.

create table atlas.flower_preparation_directives (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  harvest_batch_id uuid not null references atlas.flower_harvest_batches(id) on delete restrict,
  owner_review_task_id uuid not null references atlas.tasks(id) on delete restrict,
  preparation_occurrence_id uuid not null references atlas.planned_work_occurrences(id) on delete restrict,
  recorded_by_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  idempotency_key text not null,
  request_fingerprint text not null,
  note text,
  created_by_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_preparation_directives_farm_idempotency_unique unique (farm_id, idempotency_key),
  constraint flower_preparation_directives_owner_review_task_unique unique (owner_review_task_id),
  constraint flower_preparation_directives_occurrence_unique unique (preparation_occurrence_id),
  constraint flower_preparation_directives_id_farm_unique unique (id, farm_id),
  constraint flower_preparation_directives_idempotency_key_check
    check (char_length(btrim(idempotency_key)) between 1 and 160),
  constraint flower_preparation_directives_request_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint flower_preparation_directives_note_check
    check (note is null or char_length(note) <= 4000),
  constraint flower_preparation_directives_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.flower_preparation_directives is
  'Immutable Owner-issued instruction for turning one harvested flower batch into requested finished forms. Requested quantities are directives, not finished inventory truth.';
comment on column atlas.flower_preparation_directives.owner_review_task_id is
  'Owner decision task whose governed completion issued this directive.';
comment on column atlas.flower_preparation_directives.preparation_occurrence_id is
  'Waiting Flower Preparation occurrence released only after this directive is recorded.';

create table atlas.flower_preparation_directive_lines (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  directive_id uuid not null,
  line_number integer not null,
  crop_profile_id uuid references atlas.crop_profiles(id) on delete restrict,
  product_label text not null,
  output_kind text not null,
  requested_quantity integer not null,
  stems_per_unit integer,
  note text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_preparation_directive_lines_directive_farm_fkey
    foreign key (directive_id, farm_id)
    references atlas.flower_preparation_directives(id, farm_id)
    on delete restrict,
  constraint flower_preparation_directive_lines_number_unique unique (directive_id, line_number),
  constraint flower_preparation_directive_lines_number_check check (line_number between 1 and 12),
  constraint flower_preparation_directive_lines_product_label_check
    check (char_length(btrim(product_label)) between 1 and 160),
  constraint flower_preparation_directive_lines_output_kind_check
    check (output_kind in ('bundle', 'posy', 'bouquet', 'lobby_arrangement')),
  constraint flower_preparation_directive_lines_requested_quantity_check
    check (requested_quantity between 1 and 10000),
  constraint flower_preparation_directive_lines_bundle_size_check
    check (
      (output_kind = 'bundle' and stems_per_unit between 1 and 1000)
      or (output_kind <> 'bundle' and stems_per_unit is null)
    ),
  constraint flower_preparation_directive_lines_note_check
    check (note is null or char_length(note) <= 1000),
  constraint flower_preparation_directive_lines_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.flower_preparation_directive_lines is
  'Immutable requested preparation rows. Actual finished quantity is recorded later by Flower Preparation and is never inferred from requested_quantity.';
comment on column atlas.flower_preparation_directive_lines.crop_profile_id is
  'Canonical crop identity when the requested product maps to one harvested crop. Null is permitted for mixed/owner-labeled assembled products.';
comment on column atlas.flower_preparation_directive_lines.product_label is
  'Human-readable requested product label; it may not substitute a grade/status such as FQ or SP for crop identity.';
comment on column atlas.flower_preparation_directive_lines.requested_quantity is
  'Owner target only. It is not a claim that this quantity physically exists.';
comment on column atlas.flower_preparation_directive_lines.stems_per_unit is
  'Required only for bundle output in v1; e.g. 10 means a 10-stem bundle.';

create index flower_preparation_directives_harvest_batch_idx
  on atlas.flower_preparation_directives(harvest_batch_id, created_at);
create index flower_preparation_directive_lines_crop_profile_idx
  on atlas.flower_preparation_directive_lines(crop_profile_id)
  where crop_profile_id is not null;

alter table atlas.flower_preparation_directives enable row level security;
alter table atlas.flower_preparation_directive_lines enable row level security;

grant select on atlas.flower_preparation_directives to authenticated;
grant select on atlas.flower_preparation_directive_lines to authenticated;
grant all on atlas.flower_preparation_directives to service_role;
grant all on atlas.flower_preparation_directive_lines to service_role;

create policy flower_preparation_directives_member_read_v1
  on atlas.flower_preparation_directives
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

create policy flower_preparation_directive_lines_member_read_v1
  on atlas.flower_preparation_directive_lines
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

create or replace function atlas.prevent_flower_preparation_directive_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
begin
  raise exception 'Issued flower preparation directives are immutable; record an explicit later correction instead.'
    using errcode = '55000';
end;
$function$;

revoke all on function atlas.prevent_flower_preparation_directive_mutation_v1() from public;

create trigger flower_preparation_directives_immutable_v1
before update or delete on atlas.flower_preparation_directives
for each row execute function atlas.prevent_flower_preparation_directive_mutation_v1();

create trigger flower_preparation_directive_lines_immutable_v1
before update or delete on atlas.flower_preparation_directive_lines
for each row execute function atlas.prevent_flower_preparation_directive_mutation_v1();

create or replace function atlas.record_flower_preparation_directive_v1(
  p_owner_review_task_id uuid,
  p_lines jsonb,
  p_note text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_membership atlas.farm_memberships%rowtype;
  v_batch atlas.flower_harvest_batches%rowtype;
  v_occurrence atlas.planned_work_occurrences%rowtype;
  v_policy atlas.work_release_policies%rowtype;
  v_assignee atlas.farm_memberships%rowtype;
  v_existing atlas.flower_preparation_directives%rowtype;
  v_directive atlas.flower_preparation_directives%rowtype;
  v_clock atlas.task_dependency_clocks%rowtype;
  v_line jsonb;
  v_line_number integer := 0;
  v_crop_profile_id uuid;
  v_product_label text;
  v_output_kind text;
  v_requested_text text;
  v_requested_quantity integer;
  v_stems_text text;
  v_stems_per_unit integer;
  v_line_note text;
  v_batch_id uuid;
  v_occurrence_id uuid;
  v_assignee_id uuid;
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_fingerprint text;
  v_transition jsonb;
  v_release jsonb;
  v_worker_task_id uuid;
  v_occurrence_task_metadata jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Owner membership required.' using errcode = '42501';
  end if;

  if p_owner_review_task_id is null then
    raise exception 'Owner review task is required.' using errcode = '22023';
  end if;

  if v_key is null or char_length(v_key) > 160 then
    raise exception 'A valid directive idempotency key is required.' using errcode = '22023';
  end if;

  if v_note is not null and char_length(v_note) > 4000 then
    raise exception 'Directive note must be 4000 characters or fewer.' using errcode = '22023';
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) < 1
     or jsonb_array_length(p_lines) > 12 then
    raise exception 'Preparation directions require between 1 and 12 requested output lines.' using errcode = '22023';
  end if;

  select * into v_task
  from atlas.tasks
  where id = p_owner_review_task_id
  for update;

  if v_task.id is null then
    raise exception 'Owner harvest review task was not found.' using errcode = 'P0002';
  end if;

  select * into v_membership
  from atlas.farm_memberships
  where user_id = auth.uid()
    and farm_id = v_task.farm_id
    and active = true;

  if v_membership.id is null or v_membership.role not in ('owner', 'manager') then
    raise exception 'Owner or manager authority is required to direct harvested flowers.' using errcode = '42501';
  end if;

  if v_task.visibility_scope not in ('owner', 'management')
     or coalesce(v_task.work_class, '') <> 'owner_decision'
     or coalesce(v_task.metadata->>'task_style', '') <> 'flower_preparation_directive_review'
     or coalesce(v_task.metadata->>'flower_preparation_directive_review_version', '') <> '1' then
    raise exception 'This task is not a governed flower preparation directive review.' using errcode = '22023';
  end if;

  begin
    v_batch_id := nullif(v_task.metadata->>'flower_harvest_batch_id', '')::uuid;
    v_occurrence_id := nullif(v_task.metadata->>'flower_preparation_occurrence_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Owner harvest review task has invalid preparation linkage.' using errcode = '22023';
  end;

  if v_batch_id is null or v_occurrence_id is null then
    raise exception 'Owner harvest review task is missing its harvest batch or waiting preparation occurrence.' using errcode = '22023';
  end if;

  v_fingerprint := md5(
    p_owner_review_task_id::text || '|' || p_lines::text || '|' || coalesce(v_note, '')
  );

  select * into v_existing
  from atlas.flower_preparation_directives
  where farm_id = v_task.farm_id
    and idempotency_key = v_key;

  if v_existing.id is not null then
    if v_existing.owner_review_task_id is distinct from p_owner_review_task_id
       or v_existing.harvest_batch_id is distinct from v_batch_id
       or v_existing.preparation_occurrence_id is distinct from v_occurrence_id
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Directive idempotency key was already used for a different request.' using errcode = '22023';
    end if;

    select released_task_id into v_worker_task_id
    from atlas.planned_work_occurrences
    where id = v_existing.preparation_occurrence_id;

    return jsonb_build_object(
      'directiveId', v_existing.id,
      'ownerReviewTaskId', v_existing.owner_review_task_id,
      'harvestBatchId', v_existing.harvest_batch_id,
      'preparationOccurrenceId', v_existing.preparation_occurrence_id,
      'preparationTaskId', v_worker_task_id,
      'lineCount', (select count(*) from atlas.flower_preparation_directive_lines l where l.directive_id = v_existing.id),
      'deduplicated', true
    );
  end if;

  if v_task.status not in ('open', 'blocked') then
    raise exception 'Owner harvest review is no longer open for a new directive.' using errcode = '22023';
  end if;

  select * into v_batch
  from atlas.flower_harvest_batches
  where id = v_batch_id;

  if v_batch.id is null or v_batch.farm_id is distinct from v_task.farm_id then
    raise exception 'Linked flower harvest batch is outside this Owner review.' using errcode = '22023';
  end if;

  if not exists (
    select 1 from atlas.flower_harvest_bucket_observations h where h.batch_id = v_batch.id
  ) then
    raise exception 'Linked flower harvest batch has no recorded harvest observations.' using errcode = '22023';
  end if;

  select * into v_occurrence
  from atlas.planned_work_occurrences
  where id = v_occurrence_id
  for update;

  if v_occurrence.id is null
     or v_occurrence.farm_id is distinct from v_task.farm_id
     or v_occurrence.source_kind is distinct from 'flower_harvest_batch'
     or v_occurrence.source_id is distinct from v_batch.id
     or coalesce(v_occurrence.task_payload->>'task_type', '') <> 'flower_preparation' then
    raise exception 'Waiting Flower Preparation occurrence does not match this harvest review.' using errcode = '22023';
  end if;

  if v_occurrence.released_task_id is not null
     or v_occurrence.gate_satisfied_at is not null
     or v_occurrence.state not in ('planned', 'failed') then
    raise exception 'Flower Preparation has already been exposed or satisfied before Owner direction.' using errcode = '22023';
  end if;

  select * into v_policy
  from atlas.work_release_policies
  where id = v_occurrence.release_policy_id;

  if v_policy.id is null
     or v_policy.gate_type not in ('predecessor', 'event', 'state', 'composite')
     or coalesce(v_policy.gate_config->>'engine', '') <> 'task_dependency_clock_v1' then
    raise exception 'Waiting Flower Preparation occurrence is not governed by the dependency continuation contract.' using errcode = '22023';
  end if;

  begin
    v_assignee_id := nullif(v_occurrence.task_payload->>'assigned_membership_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Waiting Flower Preparation occurrence has an invalid assignee.' using errcode = '22023';
  end;

  select * into v_assignee
  from atlas.farm_memberships
  where id = v_assignee_id;

  if v_assignee.id is null
     or not v_assignee.active
     or v_assignee.farm_id is distinct from v_task.farm_id
     or coalesce(v_occurrence.task_payload->>'visibility_scope', '') <> 'assigned_worker' then
    raise exception 'Waiting Flower Preparation occurrence has no valid assigned worker.' using errcode = '22023';
  end if;

  -- Validate every row before any durable directive is admitted. Crop identity,
  -- when supplied, must be physically present in the linked harvest batch.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Each preparation direction must be an object.' using errcode = '22023';
    end if;

    v_product_label := nullif(btrim(coalesce(v_line->>'productLabel', '')), '');
    v_output_kind := lower(btrim(coalesce(v_line->>'outputKind', '')));
    v_requested_text := btrim(coalesce(v_line->>'requestedQuantity', ''));
    v_stems_text := btrim(coalesce(v_line->>'stemsPerUnit', ''));
    v_line_note := nullif(btrim(coalesce(v_line->>'note', '')), '');

    if v_product_label is null or char_length(v_product_label) > 160 then
      raise exception 'Each preparation direction requires a product label of 160 characters or fewer.' using errcode = '22023';
    end if;

    if lower(v_product_label) in ('fq', 'florist quality', 'sp', 'spent') then
      raise exception 'Preparation product must name a crop or finished product, not the FQ/SP harvest grade or status.' using errcode = '22023';
    end if;

    if v_output_kind not in ('bundle', 'posy', 'bouquet', 'lobby_arrangement') then
      raise exception 'Preparation output kind must be bundle, posy, bouquet, or lobby_arrangement.' using errcode = '22023';
    end if;

    if v_requested_text !~ '^[0-9]+$' then
      raise exception 'Requested preparation quantity must be a whole number.' using errcode = '22023';
    end if;
    v_requested_quantity := v_requested_text::integer;
    if v_requested_quantity < 1 or v_requested_quantity > 10000 then
      raise exception 'Requested preparation quantity must be between 1 and 10000.' using errcode = '22023';
    end if;

    if v_output_kind = 'bundle' then
      if v_stems_text !~ '^[0-9]+$' then
        raise exception 'A bundle direction requires a whole-number stems-per-bundle value.' using errcode = '22023';
      end if;
      v_stems_per_unit := v_stems_text::integer;
      if v_stems_per_unit < 1 or v_stems_per_unit > 1000 then
        raise exception 'Bundle size must be between 1 and 1000 stems.' using errcode = '22023';
      end if;
    else
      if v_stems_text <> '' then
        raise exception 'Stems per unit is only supported for bundle directions in v1.' using errcode = '22023';
      end if;
      v_stems_per_unit := null;
    end if;

    if v_line_note is not null and char_length(v_line_note) > 1000 then
      raise exception 'Preparation line note must be 1000 characters or fewer.' using errcode = '22023';
    end if;

    begin
      v_crop_profile_id := nullif(btrim(coalesce(v_line->>'cropProfileId', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Preparation cropProfileId must be a valid UUID.' using errcode = '22023';
    end;

    if v_crop_profile_id is not null then
      if not exists (select 1 from atlas.crop_profiles cp where cp.id = v_crop_profile_id) then
        raise exception 'Preparation crop profile was not found.' using errcode = '22023';
      end if;

      if not exists (
        select 1
        from atlas.flower_harvest_bucket_observations h
        join atlas.crop_cycles c on c.id = h.crop_cycle_id
        where h.batch_id = v_batch.id
          and c.crop_profile_id = v_crop_profile_id
      ) then
        raise exception 'Preparation crop identity is not present in the linked harvest batch.' using errcode = '22023';
      end if;
    end if;
  end loop;

  insert into atlas.flower_preparation_directives (
    farm_id,
    harvest_batch_id,
    owner_review_task_id,
    preparation_occurrence_id,
    recorded_by_membership_id,
    idempotency_key,
    request_fingerprint,
    note,
    created_by_user_id,
    metadata
  ) values (
    v_task.farm_id,
    v_batch.id,
    v_task.id,
    v_occurrence.id,
    v_membership.id,
    v_key,
    v_fingerprint,
    v_note,
    auth.uid(),
    jsonb_build_object(
      'version', 'flower_preparation_directive_v1',
      'truthBoundary', 'owner_requested_preparation',
      'requestedQuantityIsPhysicalTruth', false,
      'assigneeMembershipId', v_assignee.id
    )
  ) returning * into v_directive;

  v_line_number := 0;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    v_product_label := btrim(v_line->>'productLabel');
    v_output_kind := lower(btrim(v_line->>'outputKind'));
    v_requested_quantity := btrim(v_line->>'requestedQuantity')::integer;
    v_line_note := nullif(btrim(coalesce(v_line->>'note', '')), '');
    v_crop_profile_id := nullif(btrim(coalesce(v_line->>'cropProfileId', '')), '')::uuid;
    v_stems_per_unit := case
      when v_output_kind = 'bundle' then btrim(v_line->>'stemsPerUnit')::integer
      else null
    end;

    insert into atlas.flower_preparation_directive_lines (
      farm_id,
      directive_id,
      line_number,
      crop_profile_id,
      product_label,
      output_kind,
      requested_quantity,
      stems_per_unit,
      note,
      metadata
    ) values (
      v_task.farm_id,
      v_directive.id,
      v_line_number,
      v_crop_profile_id,
      v_product_label,
      v_output_kind,
      v_requested_quantity,
      v_stems_per_unit,
      v_line_note,
      jsonb_build_object(
        'identityBasis', case when v_crop_profile_id is null then 'owner_label' else 'crop_profile' end,
        'truthBoundary', 'owner_requested_preparation'
      )
    );
  end loop;

  v_occurrence_task_metadata := coalesce(v_occurrence.task_payload->'metadata', '{}'::jsonb)
    || jsonb_build_object(
      'flower_preparation_directive_id', v_directive.id,
      'flower_preparation_directive_version', 1,
      'requested_output_line_count', v_line_number,
      'requested_output_truth_boundary', 'owner_requested_preparation'
    );

  update atlas.planned_work_occurrences
  set task_payload = jsonb_set(coalesce(task_payload, '{}'::jsonb), '{metadata}', v_occurrence_task_metadata, true),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'flowerPreparationDirectiveId', v_directive.id,
        'flowerPreparationDirectiveVersion', 1,
        'ownerReviewTaskId', v_task.id
      ),
      work_lane = 'process_continuation',
      commitment_kind = 'dependency',
      updated_at = now()
  where id = v_occurrence.id;

  select * into v_clock
  from atlas.task_dependency_clocks
  where downstream_occurrence_id = v_occurrence.id
  for update;

  if v_clock.id is not null then
    if v_clock.source_task_id is distinct from v_task.id
       or v_clock.state <> 'waiting'
       or v_clock.source_transitions <> array['done']::text[]
       or v_clock.delay_interval <> interval '0 seconds' then
      raise exception 'Waiting Flower Preparation occurrence already has a conflicting dependency clock.' using errcode = '22023';
    end if;
  else
    insert into atlas.task_dependency_clocks (
      farm_id,
      source_task_id,
      downstream_occurrence_id,
      source_transitions,
      delay_interval,
      state,
      notification_policy,
      metadata
    ) values (
      v_task.farm_id,
      v_task.id,
      v_occurrence.id,
      array['done']::text[],
      interval '0 seconds',
      'waiting',
      jsonb_build_object(
        'notify_when_ready', true,
        'ready_title', 'Harvest preparation ready',
        'ready_body', 'Owner directions are ready. Prepare the harvested flowers.',
        'importance', 'high'
      ),
      jsonb_build_object(
        'version', 'flower_preparation_directive_v1',
        'flower_preparation_directive_id', v_directive.id,
        'release_reason', 'owner_preparation_directive_recorded'
      )
    ) returning * into v_clock;
  end if;

  v_transition := atlas.record_task_transition_v1(
    v_task.id,
    'done',
    'flower-preparation-directive:' || v_directive.id::text,
    null,
    v_note,
    null,
    'decide',
    'flower_preparation_directive',
    jsonb_build_object(
      'completion_source', 'flower_preparation_directive',
      'flower_preparation_directive_id', v_directive.id,
      'flower_harvest_batch_id', v_batch.id,
      'preparation_occurrence_id', v_occurrence.id,
      'requested_output_line_count', v_line_number,
      'requested_quantity_is_physical_truth', false
    ),
    null
  );

  -- The task-transition trigger starts zero-delay dependency clocks. If normal
  -- backlog admission did not release the continuation, release the reviewed
  -- dependency continuation outside backlog capacity, then advance once more
  -- so the clock reaches released state and its Ready notification is emitted.
  v_release := atlas.release_ready_task_dependency_continuations_v1(now(), 100);
  perform atlas.advance_task_dependency_clocks_v1(now(), 100);

  select released_task_id into v_worker_task_id
  from atlas.planned_work_occurrences
  where id = v_occurrence.id;

  if v_worker_task_id is null then
    raise exception 'Flower Preparation did not release after Owner direction; directive transaction was rolled back.' using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from atlas.tasks t
    where t.id = v_worker_task_id
      and t.farm_id = v_task.farm_id
      and t.task_type = 'flower_preparation'
      and t.metadata->>'flower_preparation_directive_id' = v_directive.id::text
  ) then
    raise exception 'Released task does not preserve the flower preparation directive linkage.' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'directiveId', v_directive.id,
    'ownerReviewTaskId', v_task.id,
    'harvestBatchId', v_batch.id,
    'preparationOccurrenceId', v_occurrence.id,
    'preparationTaskId', v_worker_task_id,
    'lineCount', v_line_number,
    'transition', v_transition,
    'continuationRelease', v_release,
    'deduplicated', false
  );
end;
$function$;

revoke all on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) from public;
grant execute on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) to authenticated;

comment on function atlas.record_flower_preparation_directive_v1(uuid, jsonb, text, text) is
  'Atomically records immutable Owner requested preparation rows, completes the governed Owner harvest-review task through the canonical transition engine, and releases the linked waiting Flower Preparation continuation. Does not create finished inventory.';
