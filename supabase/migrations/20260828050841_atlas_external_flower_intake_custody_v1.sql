-- Atlas external flower intake custody v1
--
-- Purpose:
--   Record flowers that enter the Harvest-day custody packet from outside Elm's
--   canonical crop-cycle graph: foraged material, purchased flowers, and gifts.
--
-- Truth boundaries:
--   flower_harvest_bucket_observations -> flowers cut from a known Elm crop cycle
--   flower_external_intakes            -> one external source event for a Harvest task
--   flower_external_intake_lines       -> flower/color/unit/quantity physically received
--
-- External intake is custody truth, not crop-cycle truth, not a sales order, and
-- not finished Ready inventory. This migration does not create/release tasks and
-- does not change the existing post-harvest approval lock.

create table atlas.flower_external_intakes (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  harvest_task_id uuid not null references atlas.tasks(id) on delete restrict,
  harvest_batch_id uuid not null references atlas.flower_harvest_batches(id) on delete restrict,
  recorded_by_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  intake_date date not null default ((now() at time zone 'America/Chicago')::date),
  source_kind text not null,
  source_label text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  created_by_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_external_intakes_farm_idempotency_unique unique (farm_id, idempotency_key),
  constraint flower_external_intakes_id_farm_unique unique (id, farm_id),
  constraint flower_external_intakes_source_kind_check
    check (source_kind in ('foraged', 'purchased', 'gifted')),
  constraint flower_external_intakes_source_label_check
    check (char_length(btrim(source_label)) between 1 and 200),
  constraint flower_external_intakes_idempotency_key_check
    check (char_length(btrim(idempotency_key)) between 1 and 160),
  constraint flower_external_intakes_request_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint flower_external_intakes_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.flower_external_intakes is
  'One external flower custody event attached to a Harvest task and its flower_harvest_batch. It records provenance without pretending external flowers came from an Elm crop cycle.';
comment on column atlas.flower_external_intakes.harvest_batch_id is
  'Shared Harvest-day flower custody batch. External lines join the same packet as Elm harvest observations without creating fake crop_cycle_id values.';
comment on column atlas.flower_external_intakes.source_kind is
  'How the external material entered custody: foraged, purchased, or gifted.';
comment on column atlas.flower_external_intakes.source_label is
  'Human-readable provenance such as Mary''s garden, roadside, or a wholesaler.';

create table atlas.flower_external_intake_lines (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  intake_id uuid not null,
  line_number integer not null,
  flower_label text not null,
  color_label text,
  count_unit text not null,
  quantity integer not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_external_intake_lines_intake_farm_fkey
    foreign key (intake_id, farm_id)
    references atlas.flower_external_intakes(id, farm_id)
    on delete restrict,
  constraint flower_external_intake_lines_number_unique unique (intake_id, line_number),
  constraint flower_external_intake_lines_number_check check (line_number between 1 and 24),
  constraint flower_external_intake_lines_flower_label_check
    check (char_length(btrim(flower_label)) between 1 and 160),
  constraint flower_external_intake_lines_color_label_check
    check (color_label is null or char_length(btrim(color_label)) between 1 and 160),
  constraint flower_external_intake_lines_count_unit_check
    check (count_unit in ('stem', 'bucket', 'bundle')),
  constraint flower_external_intake_lines_quantity_check
    check (quantity between 1 and 10000),
  constraint flower_external_intake_lines_metadata_object_check
    check (jsonb_typeof(metadata) = 'object')
);

comment on table atlas.flower_external_intake_lines is
  'Physical external flower quantities received under one provenance event. Each row binds flower + optional color + chosen count unit + quantity.';
comment on column atlas.flower_external_intake_lines.flower_label is
  'Observed flower/material identity supplied by the worker. Grade/status labels such as FQ or SP are not accepted as flower identity.';
comment on column atlas.flower_external_intake_lines.color_label is
  'Optional observed color for this specific flower/material row.';
comment on column atlas.flower_external_intake_lines.count_unit is
  'The physical unit chosen when the row was defined: stem, bucket, or bundle.';
comment on column atlas.flower_external_intake_lines.quantity is
  'Physical quantity received in count_unit. Zero is not a custody event and is not persisted.';

create index flower_external_intakes_harvest_task_idx
  on atlas.flower_external_intakes(harvest_task_id, created_at);
create index flower_external_intakes_harvest_batch_idx
  on atlas.flower_external_intakes(harvest_batch_id, created_at);
create index flower_external_intake_lines_intake_idx
  on atlas.flower_external_intake_lines(intake_id, line_number);

alter table atlas.flower_external_intakes enable row level security;
alter table atlas.flower_external_intake_lines enable row level security;

grant select on atlas.flower_external_intakes to authenticated;
grant select on atlas.flower_external_intake_lines to authenticated;
grant all on atlas.flower_external_intakes to service_role;
grant all on atlas.flower_external_intake_lines to service_role;

create policy flower_external_intakes_member_read_v1
  on atlas.flower_external_intakes
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

create policy flower_external_intake_lines_member_read_v1
  on atlas.flower_external_intake_lines
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

create or replace function atlas.record_external_flower_intake_core_v1(
  p_task_id uuid,
  p_effective_membership_id uuid,
  p_effective_role text,
  p_source_kind text,
  p_source_label text,
  p_lines jsonb,
  p_idempotency_key text,
  p_operator_mode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_existing atlas.flower_external_intakes%rowtype;
  v_intake atlas.flower_external_intakes%rowtype;
  v_batch_id uuid;
  v_source_kind text := lower(btrim(coalesce(p_source_kind, '')));
  v_source_label text := nullif(btrim(coalesce(p_source_label, '')), '');
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_fingerprint text;
  v_line jsonb;
  v_line_number integer := 0;
  v_flower_label text;
  v_color_label text;
  v_unit_raw text;
  v_count_unit text;
  v_quantity_text text;
  v_quantity integer;
  v_rows jsonb;
begin
  if p_task_id is null then
    raise exception 'Harvest task is required.' using errcode = '22023';
  end if;

  if v_key is null or char_length(v_key) > 160 then
    raise exception 'A valid external intake idempotency key is required.' using errcode = '22023';
  end if;

  if v_source_kind not in ('foraged', 'purchased', 'gifted') then
    raise exception 'External intake source must be Foraged, Purchased, or Gifted.' using errcode = '22023';
  end if;

  if v_source_label is null or char_length(v_source_label) > 200 then
    raise exception 'External intake source/place is required and must be 200 characters or fewer.' using errcode = '22023';
  end if;

  if p_lines is null
     or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) < 1
     or jsonb_array_length(p_lines) > 24 then
    raise exception 'External intake requires between 1 and 24 flower rows.' using errcode = '22023';
  end if;

  select *
  into v_task
  from atlas.tasks
  where id = p_task_id
  for update;

  if v_task.id is null then
    raise exception 'Weekly Harvest task not found.' using errcode = 'P0002';
  end if;

  if v_task.status not in ('open', 'blocked')
     or v_task.task_type <> 'harvest'
     or v_task.task_series_key <> 'anna_harvest_thursday_weekly' then
    raise exception 'External intake can only be recorded on an open Weekly Harvest card.' using errcode = '22023';
  end if;

  select *
  into v_member
  from atlas.farm_memberships
  where id = p_effective_membership_id;

  if v_member.id is null
     or not v_member.active
     or v_member.farm_id is distinct from v_task.farm_id then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  if p_effective_role not in ('owner', 'manager', 'farm_hand') then
    raise exception 'Harvest access denied.' using errcode = '42501';
  end if;

  if p_effective_role = 'farm_hand'
     and v_task.assigned_membership_id is distinct from p_effective_membership_id then
    raise exception 'Weekly Harvest is not assigned to this worker.' using errcode = '42501';
  end if;

  v_fingerprint := md5(
    jsonb_build_object(
      'taskId', p_task_id,
      'sourceKind', v_source_kind,
      'sourceLabel', v_source_label,
      'lines', p_lines
    )::text
  );

  select *
  into v_existing
  from atlas.flower_external_intakes
  where farm_id = v_task.farm_id
    and idempotency_key = v_key;

  if v_existing.id is not null then
    if v_existing.harvest_task_id is distinct from p_task_id
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'External intake idempotency key was already used for a different request.'
        using errcode = '23505';
    end if;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'lineId', l.id,
          'lineNumber', l.line_number,
          'flowerLabel', l.flower_label,
          'colorLabel', l.color_label,
          'countUnit', l.count_unit,
          'quantity', l.quantity
        )
        order by l.line_number
      ),
      '[]'::jsonb
    )
    into v_rows
    from atlas.flower_external_intake_lines l
    where l.intake_id = v_existing.id;

    return jsonb_build_object(
      'contractVersion', 'external_flower_intake_v1',
      'deduplicated', true,
      'intakeId', v_existing.id,
      'harvestTaskId', v_existing.harvest_task_id,
      'harvestBatchId', v_existing.harvest_batch_id,
      'sourceKind', v_existing.source_kind,
      'sourceLabel', v_existing.source_label,
      'lines', v_rows
    );
  end if;

  -- Join external flowers to the same Harvest-day batch used by current Weekly
  -- Harvest field observations. Merely creating/reusing the batch does not create
  -- a crop observation and therefore does not trigger flower preparation.
  insert into atlas.flower_harvest_batches(
    farm_id,
    harvest_date,
    recorded_by_membership_id,
    batch_key,
    metadata,
    created_by_user_id
  )
  values (
    v_task.farm_id,
    coalesce(v_task.due_date, (now() at time zone 'America/Chicago')::date),
    p_effective_membership_id,
    'weekly-harvest:' || v_task.id::text,
    jsonb_build_object(
      'weeklyHarvestTaskId', v_task.id,
      'externalIntakePresent', true,
      'externalIntakeContract', 'external_flower_intake_v1'
    ),
    auth.uid()
  )
  on conflict(farm_id, batch_key) do update
  set metadata = coalesce(atlas.flower_harvest_batches.metadata, '{}'::jsonb)
        || jsonb_build_object(
             'externalIntakePresent', true,
             'externalIntakeContract', 'external_flower_intake_v1'
           ),
      updated_at = now()
  returning id into v_batch_id;

  insert into atlas.flower_external_intakes(
    farm_id,
    harvest_task_id,
    harvest_batch_id,
    recorded_by_membership_id,
    intake_date,
    source_kind,
    source_label,
    idempotency_key,
    request_fingerprint,
    created_by_user_id,
    metadata
  )
  values (
    v_task.farm_id,
    v_task.id,
    v_batch_id,
    p_effective_membership_id,
    coalesce(v_task.due_date, (now() at time zone 'America/Chicago')::date),
    v_source_kind,
    v_source_label,
    v_key,
    v_fingerprint,
    auth.uid(),
    jsonb_build_object(
      'contractVersion', 'external_flower_intake_v1',
      'operatorMode', p_operator_mode,
      'truthBoundary', 'external_custody_not_crop_cycle'
    )
  )
  returning * into v_intake;

  for v_line, v_line_number in
    select value, ordinality::integer
    from jsonb_array_elements(p_lines) with ordinality
  loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Every external intake row must be an object.' using errcode = '22023';
    end if;

    v_flower_label := nullif(btrim(coalesce(v_line ->> 'flowerLabel', '')), '');
    v_color_label := nullif(btrim(coalesce(v_line ->> 'colorLabel', '')), '');
    v_unit_raw := lower(btrim(coalesce(v_line ->> 'countUnit', '')));
    v_quantity_text := btrim(coalesce(v_line ->> 'quantity', ''));

    if v_flower_label is null or char_length(v_flower_label) > 160 then
      raise exception 'Each external intake row needs a flower/material name of 160 characters or fewer.'
        using errcode = '22023';
    end if;

    if lower(v_flower_label) in ('fq', 'florist quality', 'sp', 'spent') then
      raise exception 'FQ/SP are condition labels, not flower identity. Record the flower/material name.'
        using errcode = '22023';
    end if;

    if v_color_label is not null and char_length(v_color_label) > 160 then
      raise exception 'External intake color must be 160 characters or fewer.' using errcode = '22023';
    end if;

    v_count_unit := case
      when v_unit_raw in ('stem', 'stems') then 'stem'
      when v_unit_raw in ('bucket', 'buckets') then 'bucket'
      when v_unit_raw in ('bundle', 'bundles', 'bunch', 'bunches') then 'bundle'
      else null
    end;

    if v_count_unit is null then
      raise exception 'Each external intake row must count by stems, buckets, or bundles.'
        using errcode = '22023';
    end if;

    if v_quantity_text !~ '^[0-9]+$' then
      raise exception 'Each external intake row needs a whole-number quantity.' using errcode = '22023';
    end if;

    begin
      v_quantity := v_quantity_text::integer;
    exception when others then
      raise exception 'External intake quantity is outside the supported range.' using errcode = '22023';
    end;

    if v_quantity < 1 or v_quantity > 10000 then
      raise exception 'External intake quantity must be between 1 and 10000.' using errcode = '22023';
    end if;

    insert into atlas.flower_external_intake_lines(
      farm_id,
      intake_id,
      line_number,
      flower_label,
      color_label,
      count_unit,
      quantity,
      metadata
    )
    values (
      v_task.farm_id,
      v_intake.id,
      v_line_number,
      v_flower_label,
      v_color_label,
      v_count_unit,
      v_quantity,
      jsonb_build_object(
        'contractVersion', 'external_flower_intake_v1',
        'sourceKind', v_source_kind,
        'sourceLabel', v_source_label
      )
    );
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'lineId', l.id,
        'lineNumber', l.line_number,
        'flowerLabel', l.flower_label,
        'colorLabel', l.color_label,
        'countUnit', l.count_unit,
        'quantity', l.quantity
      )
      order by l.line_number
    ),
    '[]'::jsonb
  )
  into v_rows
  from atlas.flower_external_intake_lines l
  where l.intake_id = v_intake.id;

  return jsonb_build_object(
    'contractVersion', 'external_flower_intake_v1',
    'deduplicated', false,
    'intakeId', v_intake.id,
    'harvestTaskId', v_task.id,
    'harvestBatchId', v_batch_id,
    'sourceKind', v_source_kind,
    'sourceLabel', v_source_label,
    'lines', v_rows
  );
end;
$function$;

revoke all on function atlas.record_external_flower_intake_core_v1(
  uuid, uuid, text, text, text, jsonb, text, boolean
) from public, anon, authenticated;

create or replace function atlas.record_external_flower_intake_for_member_v1(
  p_farm_id uuid,
  p_task_id uuid,
  p_source_kind text,
  p_source_label text,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_role text;
  v_membership uuid;
begin
  v_role := atlas.current_farm_role(p_farm_id);
  v_membership := atlas.current_membership_id(p_farm_id);

  if auth.uid() is null or v_role is null or v_membership is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  return atlas.record_external_flower_intake_core_v1(
    p_task_id,
    v_membership,
    v_role,
    p_source_kind,
    p_source_label,
    p_lines,
    p_idempotency_key,
    false
  );
end;
$function$;

create or replace function atlas.owner_operator_record_external_flower_intake_v1(
  p_effective_membership_id uuid,
  p_task_id uuid,
  p_source_kind text,
  p_source_label text,
  p_lines jsonb,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_context jsonb;
begin
  v_context := atlas.owner_operator_context_v1(p_effective_membership_id);

  return atlas.record_external_flower_intake_core_v1(
    p_task_id,
    (v_context #>> '{effective,membershipId}')::uuid,
    v_context #>> '{effective,role}',
    p_source_kind,
    p_source_label,
    p_lines,
    p_idempotency_key,
    true
  );
end;
$function$;

revoke all on function atlas.record_external_flower_intake_for_member_v1(
  uuid, uuid, text, text, jsonb, text
) from public, anon;
revoke all on function atlas.owner_operator_record_external_flower_intake_v1(
  uuid, uuid, text, text, jsonb, text
) from public, anon;

grant execute on function atlas.record_external_flower_intake_for_member_v1(
  uuid, uuid, text, text, jsonb, text
) to authenticated;
grant execute on function atlas.owner_operator_record_external_flower_intake_v1(
  uuid, uuid, text, text, jsonb, text
) to authenticated;

grant execute on function atlas.record_external_flower_intake_for_member_v1(
  uuid, uuid, text, text, jsonb, text
) to service_role;
grant execute on function atlas.owner_operator_record_external_flower_intake_v1(
  uuid, uuid, text, text, jsonb, text
) to service_role;

comment on function atlas.record_external_flower_intake_for_member_v1(
  uuid, uuid, text, text, jsonb, text
) is
  'Records external flower custody on an assigned Weekly Harvest task. Does not create crop-cycle observations, finished inventory, or downstream tasks.';

comment on function atlas.owner_operator_record_external_flower_intake_v1(
  uuid, uuid, text, text, jsonb, text
) is
  'Owner-operator form of external flower intake custody recording, preserving the effective worker membership and operator provenance.';