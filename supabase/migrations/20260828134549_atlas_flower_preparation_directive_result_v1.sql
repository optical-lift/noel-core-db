create table atlas.flower_preparation_directive_results (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  directive_id uuid not null references atlas.flower_preparation_directives(id) on delete restrict,
  preparation_task_id uuid not null references atlas.tasks(id) on delete restrict,
  recorded_by_membership_id uuid not null references atlas.farm_memberships(id) on delete restrict,
  idempotency_key text not null,
  request_fingerprint text not null,
  created_by_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_preparation_directive_results_farm_idempotency_unique unique (farm_id, idempotency_key),
  constraint flower_preparation_directive_results_directive_unique unique (directive_id),
  constraint flower_preparation_directive_results_task_unique unique (preparation_task_id),
  constraint flower_preparation_directive_results_id_farm_unique unique (id, farm_id),
  constraint flower_preparation_directive_results_key_check check (char_length(btrim(idempotency_key)) between 1 and 160),
  constraint flower_preparation_directive_results_fingerprint_check check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint flower_preparation_directive_results_metadata_object_check check (jsonb_typeof(metadata) = 'object')
);

create table atlas.flower_preparation_directive_result_lines (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  result_id uuid not null,
  directive_line_id uuid not null references atlas.flower_preparation_directive_lines(id) on delete restrict,
  actual_quantity integer not null,
  note text,
  created_at timestamptz not null default now(),
  constraint flower_preparation_directive_result_lines_result_farm_fkey
    foreign key (result_id, farm_id)
    references atlas.flower_preparation_directive_results(id, farm_id)
    on delete restrict,
  constraint flower_preparation_directive_result_lines_result_line_unique unique (result_id, directive_line_id),
  constraint flower_preparation_directive_result_lines_directive_line_unique unique (directive_line_id),
  constraint flower_preparation_directive_result_lines_quantity_check check (actual_quantity between 0 and 10000),
  constraint flower_preparation_directive_result_lines_note_check check (note is null or char_length(note) <= 1000)
);

comment on table atlas.flower_preparation_directive_results is
  'Immutable worker final tally for one Owner-issued flower preparation directive. This records finished physical output counts only; it does not itself create Ready inventory.';
comment on column atlas.flower_preparation_directive_result_lines.actual_quantity is
  'Worker-confirmed number actually finished for the immutable requested line. Zero is valid physical truth.';

create index flower_preparation_directive_results_created_idx
  on atlas.flower_preparation_directive_results(farm_id, created_at desc);

alter table atlas.flower_preparation_directive_results enable row level security;
alter table atlas.flower_preparation_directive_result_lines enable row level security;

grant select on atlas.flower_preparation_directive_results to authenticated;
grant select on atlas.flower_preparation_directive_result_lines to authenticated;
grant all on atlas.flower_preparation_directive_results to service_role;
grant all on atlas.flower_preparation_directive_result_lines to service_role;

create policy flower_preparation_directive_results_member_read_v1
  on atlas.flower_preparation_directive_results
  for select to authenticated
  using (atlas.is_farm_member(farm_id));

create policy flower_preparation_directive_result_lines_member_read_v1
  on atlas.flower_preparation_directive_result_lines
  for select to authenticated
  using (atlas.is_farm_member(farm_id));

create or replace function atlas.prevent_flower_preparation_directive_result_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
begin
  raise exception 'Recorded flower preparation final tallies are immutable; use an explicit governed correction.' using errcode = '55000';
end;
$function$;

revoke all on function atlas.prevent_flower_preparation_directive_result_mutation_v1() from public;

create trigger flower_preparation_directive_results_immutable_v1
before update or delete on atlas.flower_preparation_directive_results
for each row execute function atlas.prevent_flower_preparation_directive_result_mutation_v1();

create trigger flower_preparation_directive_result_lines_immutable_v1
before update or delete on atlas.flower_preparation_directive_result_lines
for each row execute function atlas.prevent_flower_preparation_directive_result_mutation_v1();

create or replace function atlas.record_flower_preparation_directive_result_for_member_v1(
  p_task_id uuid,
  p_actual_lines jsonb,
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
  v_directive atlas.flower_preparation_directives%rowtype;
  v_existing atlas.flower_preparation_directive_results%rowtype;
  v_result atlas.flower_preparation_directive_results%rowtype;
  v_line jsonb;
  v_line_id uuid;
  v_actual_text text;
  v_actual_quantity integer;
  v_note text;
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_fingerprint text;
  v_directive_id uuid;
  v_planned_occurrence_id uuid;
  v_expected_count integer;
  v_seen_line_ids uuid[] := '{}'::uuid[];
  v_transition jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated assigned farm member required.' using errcode = '42501';
  end if;

  if p_task_id is null then
    raise exception 'Flower preparation task is required.' using errcode = '22023';
  end if;

  if v_key is null or char_length(v_key) > 160 then
    raise exception 'A valid final-tally idempotency key is required.' using errcode = '22023';
  end if;

  if p_actual_lines is null or jsonb_typeof(p_actual_lines) <> 'array'
     or jsonb_array_length(p_actual_lines) < 1
     or jsonb_array_length(p_actual_lines) > 12 then
    raise exception 'Final tally requires between 1 and 12 actual lines.' using errcode = '22023';
  end if;

  select * into v_task
  from atlas.tasks
  where id = p_task_id
  for update;

  if v_task.id is null then
    raise exception 'Flower preparation task was not found.' using errcode = 'P0002';
  end if;

  select * into v_membership
  from atlas.farm_memberships
  where user_id = auth.uid()
    and farm_id = v_task.farm_id
    and active = true
  limit 1;

  if v_membership.id is null
     or v_membership.role not in ('farm_hand', 'manager')
     or v_task.visibility_scope <> 'assigned_worker'
     or v_task.assigned_membership_id is distinct from v_membership.id then
    raise exception 'This final tally is not assigned to the signed-in farm member.' using errcode = '42501';
  end if;

  if v_task.task_type <> 'flower_preparation'
     or coalesce(v_task.metadata->>'task_style', '') <> 'flower_preparation'
     or coalesce(v_task.metadata->>'requires_owner_preparation_directive', 'false') <> 'true'
     or coalesce(v_task.metadata->>'flower_preparation_directive_version', '') <> '1' then
    raise exception 'This task is not governed Owner-directed flower preparation.' using errcode = '22023';
  end if;

  begin
    v_directive_id := nullif(v_task.metadata->>'flower_preparation_directive_id', '')::uuid;
    v_planned_occurrence_id := nullif(v_task.metadata->>'planned_occurrence_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'Flower preparation task has invalid directive custody.' using errcode = '22023';
  end;

  if v_directive_id is null or v_planned_occurrence_id is null then
    raise exception 'Flower preparation task is missing directive custody.' using errcode = '22023';
  end if;

  select * into v_directive
  from atlas.flower_preparation_directives
  where id = v_directive_id;

  if v_directive.id is null
     or v_directive.farm_id is distinct from v_task.farm_id
     or v_directive.preparation_occurrence_id is distinct from v_planned_occurrence_id
     or v_directive.harvest_batch_id::text is distinct from coalesce(v_task.metadata->>'flower_harvest_batch_id', '') then
    raise exception 'Flower preparation directive does not match this worker task.' using errcode = '22023';
  end if;

  select count(*)::integer into v_expected_count
  from atlas.flower_preparation_directive_lines l
  where l.directive_id = v_directive.id;

  if v_expected_count < 1 or jsonb_array_length(p_actual_lines) <> v_expected_count then
    raise exception 'Final tally must contain every requested preparation line exactly once.' using errcode = '22023';
  end if;

  v_fingerprint := md5(p_task_id::text || '|' || v_directive.id::text || '|' || p_actual_lines::text);

  select * into v_existing
  from atlas.flower_preparation_directive_results
  where farm_id = v_task.farm_id
    and idempotency_key = v_key;

  if v_existing.id is not null then
    if v_existing.preparation_task_id is distinct from v_task.id
       or v_existing.directive_id is distinct from v_directive.id
       or v_existing.request_fingerprint is distinct from v_fingerprint then
      raise exception 'Final-tally idempotency key was already used for a different result.' using errcode = '22023';
    end if;

    return jsonb_build_object(
      'resultId', v_existing.id,
      'taskId', v_existing.preparation_task_id,
      'directiveId', v_existing.directive_id,
      'lineCount', (select count(*) from atlas.flower_preparation_directive_result_lines l where l.result_id = v_existing.id),
      'deduplicated', true
    );
  end if;

  if v_task.status not in ('open', 'blocked') then
    raise exception 'Flower preparation task is no longer open for a new final tally.' using errcode = '22023';
  end if;

  for v_line in select value from jsonb_array_elements(p_actual_lines) loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Each final-tally line must be an object.' using errcode = '22023';
    end if;

    begin
      v_line_id := nullif(btrim(coalesce(v_line->>'directiveLineId', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Each final-tally line requires a valid directiveLineId.' using errcode = '22023';
    end;

    if v_line_id is null
       or not exists (
         select 1 from atlas.flower_preparation_directive_lines dl
         where dl.id = v_line_id and dl.directive_id = v_directive.id
       ) then
      raise exception 'Final-tally line is outside this Owner directive.' using errcode = '22023';
    end if;

    if array_position(v_seen_line_ids, v_line_id) is not null then
      raise exception 'Each requested preparation line may appear only once in final tally.' using errcode = '22023';
    end if;
    v_seen_line_ids := array_append(v_seen_line_ids, v_line_id);

    v_actual_text := btrim(coalesce(v_line->>'actualQuantity', ''));
    if v_actual_text !~ '^[0-9]+$' then
      raise exception 'Actual quantity must be a whole number including zero.' using errcode = '22023';
    end if;
    v_actual_quantity := v_actual_text::integer;
    if v_actual_quantity > 10000 then
      raise exception 'Actual quantity is outside the supported range.' using errcode = '22023';
    end if;

    v_note := nullif(btrim(coalesce(v_line->>'note', '')), '');
    if v_note is not null and char_length(v_note) > 1000 then
      raise exception 'Final-tally line note must be 1000 characters or fewer.' using errcode = '22023';
    end if;
  end loop;

  insert into atlas.flower_preparation_directive_results(
    farm_id,
    directive_id,
    preparation_task_id,
    recorded_by_membership_id,
    idempotency_key,
    request_fingerprint,
    metadata
  ) values (
    v_task.farm_id,
    v_directive.id,
    v_task.id,
    v_membership.id,
    v_key,
    v_fingerprint,
    jsonb_build_object(
      'resultVersion', 1,
      'truthBoundary', 'worker_finished_preparation_tally',
      'readyInventoryCreated', false
    )
  )
  returning * into v_result;

  for v_line in select value from jsonb_array_elements(p_actual_lines) loop
    v_line_id := (v_line->>'directiveLineId')::uuid;
    v_actual_quantity := (v_line->>'actualQuantity')::integer;
    v_note := nullif(btrim(coalesce(v_line->>'note', '')), '');

    insert into atlas.flower_preparation_directive_result_lines(
      farm_id,
      result_id,
      directive_line_id,
      actual_quantity,
      note
    ) values (
      v_task.farm_id,
      v_result.id,
      v_line_id,
      v_actual_quantity,
      v_note
    );
  end loop;

  v_transition := atlas.record_task_transition_v1(
    p_task_id => v_task.id,
    p_transition => 'done',
    p_idempotency_key => 'flower-prep-final-tally:' || v_result.id::text,
    p_target_date => null,
    p_note => null,
    p_reason => null,
    p_lane_key => null,
    p_work_key => 'flower_preparation_directive_final_tally',
    p_payload => jsonb_build_object(
      'actor_user_id', auth.uid(),
      'actor_membership_id', v_membership.id,
      'actor_role', v_membership.role,
      'flowerPreparationDirectiveResultVersion', 1,
      'flowerPreparationDirectiveResultId', v_result.id,
      'flowerPreparationDirectiveId', v_directive.id,
      'actualLineCount', v_expected_count,
      'truthBoundary', 'worker_finished_preparation_tally',
      'readyInventoryCreated', false
    ),
    p_existing_field_log_id => null
  );

  return jsonb_build_object(
    'resultId', v_result.id,
    'taskId', v_task.id,
    'directiveId', v_directive.id,
    'lineCount', v_expected_count,
    'transition', v_transition,
    'deduplicated', false
  );
end;
$function$;

comment on function atlas.record_flower_preparation_directive_result_for_member_v1(uuid, jsonb, text) is
  'Assigned worker structured-result endpoint for Owner-directed flower preparation. Validates one actual quantity for every immutable directive line, records the physical final tally, and completes the worker task canonically without creating Ready inventory.';

revoke all on function atlas.record_flower_preparation_directive_result_for_member_v1(uuid, jsonb, text) from public, anon, service_role;
grant execute on function atlas.record_flower_preparation_directive_result_for_member_v1(uuid, jsonb, text) to authenticated;

with target as (
  select
    p.oid,
    format('%I.%I(%s)', n.nspname, p.proname, oidvectortypes(p.proargtypes)) as signature,
    p.prosecdef as security_definer,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_execute,
    has_function_privilege('anon', p.oid, 'EXECUTE') as anonymous_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_execute,
    (
      select count(*)::integer
      from pg_proc caller
      join pg_namespace cn on cn.oid = caller.pronamespace and cn.nspname = 'atlas'
      where caller.oid <> p.oid
        and caller.prokind = 'f'
        and (
          position(lower(p.proname) || '(' in lower(pg_get_functiondef(caller.oid))) > 0
          or position(lower(p.proname) || ' (' in lower(pg_get_functiondef(caller.oid))) > 0
        )
    ) as caller_count,
    (
      select count(*)::integer
      from pg_policies policy
      where position(lower(p.proname) || '(' in lower(coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, ''))) > 0
         or position(lower(p.proname) || ' (' in lower(coalesce(policy.qual, '') || ' ' || coalesce(policy.with_check, ''))) > 0
    ) as policy_reference_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_result_for_member_v1'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text'
)
insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  anonymous_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  registered_at,
  reviewed_at
)
select
  signature,
  'app_endpoint',
  'verified',
  'active',
  authenticated_execute,
  anonymous_execute,
  security_definer,
  service_execute,
  caller_count,
  policy_reference_count,
  jsonb_build_object(
    'source', 'atlas_flower_preparation_directive_result_v1',
    'reason', 'register_owner_directed_flower_preparation_worker_final_tally',
    'functionOid', oid,
    'classificationRuleVersion', 3,
    'truthBoundary', 'Assigned worker records actual finished quantities against immutable Owner-requested lines. This endpoint does not create Ready inventory.'
  ),
  now(),
  now()
from target
on conflict (signature) do update
set classification = excluded.classification,
    confidence = excluded.confidence,
    review_status = excluded.review_status,
    authenticated_execute_expected = excluded.authenticated_execute_expected,
    anonymous_execute_expected = excluded.anonymous_execute_expected,
    security_definer_expected = excluded.security_definer_expected,
    service_execute_expected = excluded.service_execute_expected,
    caller_count = excluded.caller_count,
    policy_reference_count = excluded.policy_reference_count,
    evidence = coalesce(atlas.authenticated_rpc_registry.evidence, '{}'::jsonb) || excluded.evidence,
    reviewed_at = now();

do $verification$
declare
  v_oid oid;
  v_drift integer;
begin
  select p.oid into v_oid
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_result_for_member_v1'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text';

  if v_oid is null then
    raise exception 'Flower preparation directive result RPC was not found.';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'Authenticated final-tally execution was not enabled.';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'Anonymous final-tally execution must remain disabled.';
  end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'Service-role final-tally execution must remain disabled.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift <> 0 then
    raise exception 'Flower preparation final-tally migration ended with % authenticated RPC drift rows.', v_drift;
  end if;
end
$verification$;