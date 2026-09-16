begin;

-- Operating Knowledge execution proof / Flower Preparation v2.
--
-- Governing rule:
--   explicit Owner bundle size wins;
--   an omitted bundle size may be supplied only by one singular established
--   Company Operating Knowledge resolution;
--   the winning knowledge identity/effect/context is preserved on the immutable
--   directive line as provenance.
--
-- v1 remains unchanged and callable. This is a new command so existing callers
-- keep their exact semantics until the application intentionally adopts v2.

do $preflight$
begin
  if to_regprocedure('atlas.record_flower_preparation_directive_v1(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v1 authority is missing.';
  end if;
  if to_regprocedure('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)') is null then
    raise exception 'Company Operating Knowledge resolver authority is missing.';
  end if;
  if to_regclass('atlas.flower_preparation_directives') is null
     or to_regclass('atlas.flower_preparation_directive_lines') is null then
    raise exception 'Flower Preparation directive custody is missing.';
  end if;
end
$preflight$;

create or replace function atlas.record_flower_preparation_directive_v2(
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
  v_farm atlas.farms%rowtype;
  v_crop_profile atlas.crop_profiles%rowtype;
  v_line jsonb;
  v_resolved_line jsonb;
  v_resolved_lines jsonb := '[]'::jsonb;
  v_line_number integer := 0;
  v_crop_profile_id uuid;
  v_product_label text;
  v_product_key text;
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
  v_context jsonb;
  v_resolution jsonb;
  v_effect jsonb;
  v_match jsonb;
  v_default_count integer := 0;
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

  -- Fingerprint the Owner's original request, before any rule-supplied default.
  -- This keeps idempotency stable if Operating Knowledge changes after issuance.
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
      'operatingKnowledgeDefaultCount', coalesce((v_existing.metadata->>'operatingKnowledgeDefaultCount')::integer, 0),
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

  select * into v_farm
  from atlas.farms
  where id = v_task.farm_id;

  if v_farm.id is null then
    raise exception 'Flower Preparation farm was not found.' using errcode = 'P0002';
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

  -- Validate the Owner request and materialize only missing bundle sizes through
  -- established Operating Knowledge. The transformed JSON remains transaction-local.
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Each preparation direction must be an object.' using errcode = '22023';
    end if;

    v_resolved_line := v_line;
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

    if v_line_note is not null and char_length(v_line_note) > 1000 then
      raise exception 'Preparation line note must be 1000 characters or fewer.' using errcode = '22023';
    end if;

    begin
      v_crop_profile_id := nullif(btrim(coalesce(v_line->>'cropProfileId', '')), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Preparation cropProfileId must be a valid UUID.' using errcode = '22023';
    end;

    v_crop_profile := null;
    if v_crop_profile_id is not null then
      select * into v_crop_profile
      from atlas.crop_profiles cp
      where cp.id = v_crop_profile_id;

      if v_crop_profile.id is null then
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

    if v_output_kind = 'bundle' then
      if v_stems_text ~ '^[0-9]+$' then
        v_stems_per_unit := v_stems_text::integer;
        if v_stems_per_unit < 1 or v_stems_per_unit > 1000 then
          raise exception 'Bundle size must be between 1 and 1000 stems.' using errcode = '22023';
        end if;
        v_resolved_line := v_resolved_line || jsonb_build_object(
          '__bundleSizeSource', 'owner_explicit'
        );
      elsif v_stems_text = '' then
        if v_farm.organization_id is null then
          raise exception 'An omitted bundle size requires institutional Organization custody.' using errcode = '22023';
        end if;

        -- Product identity comes from typed crop identity when available. Owner
        -- label is used only for the already-supported label-based directive case.
        if v_crop_profile.id is not null then
          v_product_key := case
            when lower(btrim(coalesce(v_crop_profile.crop_family, ''))) in ('sunflower', 'goldenrod')
              then lower(btrim(v_crop_profile.crop_family))
            else lower(btrim(v_crop_profile.crop_label))
          end;
        else
          v_product_key := lower(v_product_label);
        end if;

        v_context := jsonb_strip_nulls(jsonb_build_object(
          'organization_unit_id', case when v_farm.organization_unit_id is null then null else v_farm.organization_unit_id::text end,
          'category', 'cut_flower',
          'operation', 'bunch',
          'product', v_product_key
        ));

        v_resolution := atlas.resolve_company_operating_knowledge_v1(
          v_farm.organization_id,
          'standard',
          v_context,
          now()
        );

        if coalesce(v_resolution->>'resolution_state', '') <> 'resolved' then
          raise exception 'Bundle size is omitted and Operating Knowledge resolution is % for product %.',
            coalesce(v_resolution->>'resolution_state', 'unknown'), v_product_key
            using errcode = '22023';
        end if;

        v_effect := v_resolution->'resolved_effect';
        v_match := v_resolution->'matches'->0;

        if coalesce(v_effect->>'sales_unit', '') <> 'bunch'
           or coalesce(v_effect->>'quantity_unit', '') <> 'stem'
           or coalesce(v_effect->>'quantity_per_unit', '') !~ '^[0-9]+$' then
          raise exception 'Resolved Operating Knowledge does not establish a valid stem-per-bunch effect.' using errcode = '22023';
        end if;

        v_stems_per_unit := (v_effect->>'quantity_per_unit')::integer;
        if v_stems_per_unit < 1 or v_stems_per_unit > 1000 then
          raise exception 'Resolved Operating Knowledge bundle size must be between 1 and 1000 stems.' using errcode = '22023';
        end if;

        v_default_count := v_default_count + 1;
        v_resolved_line := v_resolved_line
          || jsonb_build_object(
            'stemsPerUnit', v_stems_per_unit,
            '__bundleSizeSource', 'operating_knowledge_default',
            '__operatingKnowledgeDefault', jsonb_build_object(
              'knowledgeId', v_match->>'id',
              'stableKey', v_match->>'stable_key',
              'version', (v_match->>'version')::integer,
              'statement', v_resolution->>'resolved_statement',
              'effect', v_effect,
              'context', v_context
            )
          );
      else
        raise exception 'A bundle direction stems-per-bundle value must be a whole number or omitted for governed Operating Knowledge resolution.' using errcode = '22023';
      end if;
    else
      if v_stems_text <> '' then
        raise exception 'Stems per unit is only supported for bundle directions in v2.' using errcode = '22023';
      end if;
      v_stems_per_unit := null;
    end if;

    v_resolved_lines := v_resolved_lines || jsonb_build_array(v_resolved_line);
  end loop;

  insert into atlas.flower_preparation_directives (
    farm_id, harvest_batch_id, owner_review_task_id, preparation_occurrence_id,
    recorded_by_membership_id, idempotency_key, request_fingerprint, note,
    created_by_user_id, metadata
  ) values (
    v_task.farm_id, v_batch.id, v_task.id, v_occurrence.id,
    v_membership.id, v_key, v_fingerprint, v_note, auth.uid(),
    jsonb_build_object(
      'version', 'flower_preparation_directive_v2',
      'truthBoundary', 'owner_requested_preparation',
      'requestedQuantityIsPhysicalTruth', false,
      'assigneeMembershipId', v_assignee.id,
      'bundleSizePolicy', 'owner_explicit_else_established_operating_knowledge',
      'operatingKnowledgeDefaultCount', v_default_count
    )
  ) returning * into v_directive;

  v_line_number := 0;
  for v_line in select value from jsonb_array_elements(v_resolved_lines) loop
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
      farm_id, directive_id, line_number, crop_profile_id, product_label,
      output_kind, requested_quantity, stems_per_unit, note, metadata
    ) values (
      v_task.farm_id, v_directive.id, v_line_number, v_crop_profile_id, v_product_label,
      v_output_kind, v_requested_quantity, v_stems_per_unit, v_line_note,
      jsonb_strip_nulls(
        jsonb_build_object(
          'identityBasis', case when v_crop_profile_id is null then 'owner_label' else 'crop_profile' end,
          'truthBoundary', 'owner_requested_preparation',
          'bundleSizeSource', case when v_output_kind = 'bundle' then v_line->>'__bundleSizeSource' else null end,
          'operatingKnowledgeDefault', case
            when v_line->>'__bundleSizeSource' = 'operating_knowledge_default' then v_line->'__operatingKnowledgeDefault'
            else null
          end
        )
      )
    );
  end loop;

  v_occurrence_task_metadata := coalesce(v_occurrence.task_payload->'metadata', '{}'::jsonb)
    || jsonb_build_object(
      'flower_preparation_directive_id', v_directive.id,
      'flower_preparation_directive_version', 2,
      'requested_output_line_count', v_line_number,
      'requested_output_truth_boundary', 'owner_requested_preparation',
      'operating_knowledge_default_count', v_default_count
    );

  update atlas.planned_work_occurrences
  set task_payload = jsonb_set(coalesce(task_payload, '{}'::jsonb), '{metadata}', v_occurrence_task_metadata, true),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'flowerPreparationDirectiveId', v_directive.id,
        'flowerPreparationDirectiveVersion', 2,
        'ownerReviewTaskId', v_task.id,
        'operatingKnowledgeDefaultCount', v_default_count
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
      farm_id, source_task_id, downstream_occurrence_id, source_transitions,
      delay_interval, state, notification_policy, metadata
    ) values (
      v_task.farm_id, v_task.id, v_occurrence.id, array['done']::text[],
      interval '0 seconds', 'waiting',
      jsonb_build_object(
        'notify_when_ready', true,
        'ready_title', 'Harvest preparation ready',
        'ready_body', 'Owner directions are ready. Prepare the harvested flowers.',
        'importance', 'high'
      ),
      jsonb_build_object(
        'version', 'flower_preparation_directive_v2',
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
      'flower_preparation_directive_version', 2,
      'flower_harvest_batch_id', v_batch.id,
      'preparation_occurrence_id', v_occurrence.id,
      'requested_output_line_count', v_line_number,
      'requested_quantity_is_physical_truth', false,
      'operating_knowledge_default_count', v_default_count
    ),
    null
  );

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
    'operatingKnowledgeDefaultCount', v_default_count,
    'transition', v_transition,
    'continuationRelease', v_release,
    'deduplicated', false
  );
end;
$function$;

revoke all on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)
  from public, anon, authenticated, service_role;
grant execute on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)
  to authenticated;

comment on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text) is
  'Flower Preparation v2: preserves explicit Owner bundle size; when omitted, resolves one established Company Operating Knowledge standard and records the winning rule/effect/context on the immutable directive line before releasing the governed preparation continuation.';

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
      join pg_namespace caller_namespace on caller_namespace.oid = caller.pronamespace and caller_namespace.nspname = 'atlas'
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
    and p.proname = 'record_flower_preparation_directive_v2'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text, text'
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
    'source', 'atlas_flower_preparation_operating_knowledge_default_v2',
    'reason', 'governed_operating_knowledge_default_execution_proof',
    'functionOid', oid,
    'classificationRuleVersion', 3,
    'truthBoundary', 'Owner explicit preparation remains sovereign. Only an omitted bundle size may be filled by a singular established Company Operating Knowledge standard; the applied knowledge is preserved as provenance on the immutable directive line.'
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
  v_def text;
  v_drift integer;
begin
  select p.oid, pg_get_functiondef(p.oid)
  into v_oid, v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'atlas'
    and p.proname = 'record_flower_preparation_directive_v2'
    and oidvectortypes(p.proargtypes) = 'uuid, jsonb, text, text';

  if v_oid is null then
    raise exception 'Flower Preparation v2 RPC was not found.';
  end if;
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'Authenticated Flower Preparation v2 execution was not enabled.';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') then
    raise exception 'Anonymous Flower Preparation v2 execution must remain disabled.';
  end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'Service-role Flower Preparation v2 execution must remain disabled.';
  end if;
  if position('resolve_company_operating_knowledge_v1' in v_def) = 0
     or position('owner_explicit_else_established_operating_knowledge' in v_def) = 0
     or position('operatingKnowledgeDefault' in v_def) = 0 then
    raise exception 'Flower Preparation v2 is missing its governed Operating Knowledge execution contract.';
  end if;

  select count(*) into v_drift from atlas.authenticated_rpc_registry_drift_v1();
  if v_drift <> 0 then
    raise exception 'Flower Preparation v2 registration ended with % authenticated RPC drift rows.', v_drift;
  end if;
end
$verification$;

commit;
