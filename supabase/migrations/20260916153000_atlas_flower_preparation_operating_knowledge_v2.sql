begin;

-- Flower Preparation + Company Operating Knowledge v2.
--
-- Governing boundary:
--   * record_flower_preparation_directive_v1 remains the sole authority that
--     issues the immutable Owner directive, completes Owner review, and releases
--     the waiting Flower Preparation continuation.
--   * v2 may supply a missing bundle size only from established Company
--     Operating Knowledge after a canonical crop-profile -> product binding.
--   * an explicit Owner stemsPerUnit always wins and never invokes the resolver.
--   * an unbound crop fails closed; labels/aliases are never parsed as product identity.
--   * provenance is immutable and separate from the immutable v1 directive rows.

-- The existing rule vocabulary uses product/category keys while Flower Operations
-- owns canonical crop_profile_id. This table is the explicit domain seam between
-- those identities. It is unit-scoped because Operating Knowledge itself may be.
create table atlas.flower_operating_knowledge_crop_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_unit_id uuid not null references atlas.organization_units(id) on delete cascade,
  crop_profile_id uuid not null references atlas.crop_profiles(id) on delete restrict,
  category_key text not null,
  product_key text not null,
  source_kind text not null default 'canonical_crop_profile_identity',
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint flower_operating_knowledge_crop_bindings_identity_uq
    unique (organization_unit_id, crop_profile_id),
  constraint flower_operating_knowledge_crop_bindings_category_check
    check (category_key ~ '^[a-z0-9][a-z0-9_]*$'),
  constraint flower_operating_knowledge_crop_bindings_product_check
    check (product_key ~ '^[a-z0-9][a-z0-9_]*$'),
  constraint flower_operating_knowledge_crop_bindings_source_check
    check (char_length(btrim(source_kind)) between 1 and 120),
  constraint flower_operating_knowledge_crop_bindings_provenance_object_check
    check (jsonb_typeof(provenance) = 'object')
);

comment on table atlas.flower_operating_knowledge_crop_bindings is
  'Explicit Flower-domain identity bridge from canonical crop_profile_id to Company Operating Knowledge product/category keys. Runtime labels and aliases are not identity authority.';

revoke all on table atlas.flower_operating_knowledge_crop_bindings from public, anon, authenticated;
grant select on table atlas.flower_operating_knowledge_crop_bindings to service_role;
alter table atlas.flower_operating_knowledge_crop_bindings enable row level security;

-- Provenance is kept beside, not inside, v1 immutable directive lines so v1 can
-- remain byte-for-byte untouched and remain the release authority.
create table atlas.flower_preparation_directive_line_knowledge_provenance (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  directive_id uuid not null,
  directive_line_id uuid not null references atlas.flower_preparation_directive_lines(id) on delete restrict,
  line_number integer not null,
  source_kind text not null,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid not null references atlas.organization_units(id) on delete restrict,
  binding_id uuid references atlas.flower_operating_knowledge_crop_bindings(id) on delete restrict,
  knowledge_rule_ids uuid[] not null default '{}'::uuid[],
  resolution_context jsonb not null default '{}'::jsonb,
  resolved_effect jsonb,
  applied_stems_per_unit integer,
  request_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint flower_preparation_directive_line_knowledge_provenance_directive_farm_fkey
    foreign key (directive_id, farm_id)
    references atlas.flower_preparation_directives(id, farm_id)
    on delete restrict,
  constraint flower_preparation_directive_line_knowledge_provenance_line_uq
    unique (directive_line_id),
  constraint flower_preparation_directive_line_knowledge_provenance_number_uq
    unique (directive_id, line_number),
  constraint flower_preparation_directive_line_knowledge_provenance_line_number_check
    check (line_number between 1 and 12),
  constraint flower_preparation_directive_line_knowledge_provenance_source_check
    check (source_kind in ('owner_explicit', 'operating_knowledge', 'not_applicable')),
  constraint flower_preparation_directive_line_knowledge_provenance_context_object_check
    check (jsonb_typeof(resolution_context) = 'object'),
  constraint flower_preparation_directive_line_knowledge_provenance_effect_object_check
    check (resolved_effect is null or jsonb_typeof(resolved_effect) = 'object'),
  constraint flower_preparation_directive_line_knowledge_provenance_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint flower_preparation_directive_line_knowledge_provenance_applied_stems_check
    check (applied_stems_per_unit is null or applied_stems_per_unit between 1 and 1000),
  constraint flower_preparation_directive_line_knowledge_provenance_semantics_check
    check (
      (source_kind = 'owner_explicit'
        and binding_id is null
        and cardinality(knowledge_rule_ids) = 0
        and resolved_effect is null
        and applied_stems_per_unit is not null)
      or
      (source_kind = 'operating_knowledge'
        and binding_id is not null
        and cardinality(knowledge_rule_ids) > 0
        and resolved_effect is not null
        and applied_stems_per_unit is not null)
      or
      (source_kind = 'not_applicable'
        and binding_id is null
        and cardinality(knowledge_rule_ids) = 0
        and resolved_effect is null
        and applied_stems_per_unit is null)
    )
);

comment on table atlas.flower_preparation_directive_line_knowledge_provenance is
  'Immutable provenance for bundle-size truth: explicit Owner value versus an established Operating Knowledge default. It never replaces the directive line itself.';

create or replace function atlas.prevent_flower_preparation_directive_line_knowledge_provenance_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
begin
  raise exception 'Flower preparation knowledge provenance is immutable; issue a later governed directive instead.'
    using errcode = '55000';
end;
$function$;

revoke all on function atlas.prevent_flower_preparation_directive_line_knowledge_provenance_mutation_v1() from public, anon, authenticated, service_role;

create trigger flower_preparation_directive_line_knowledge_provenance_immutable_v1
before update or delete on atlas.flower_preparation_directive_line_knowledge_provenance
for each row execute function atlas.prevent_flower_preparation_directive_line_knowledge_provenance_mutation_v1();

alter table atlas.flower_preparation_directive_line_knowledge_provenance enable row level security;
grant select on atlas.flower_preparation_directive_line_knowledge_provenance to authenticated;
grant all on atlas.flower_preparation_directive_line_knowledge_provenance to service_role;

create policy flower_preparation_directive_line_knowledge_provenance_member_read_v1
  on atlas.flower_preparation_directive_line_knowledge_provenance
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

-- First explicit bindings for the cross-domain execution proof. Generated IDs are
-- never hardcoded: both the unit and crop profiles resolve by canonical stable key.
-- Unbound profiles remain explicit-only until a governed binding is established.
do $seed$
declare
  v_unit_id uuid;
  v_match_count integer;
  v_insert_count integer;
begin
  select count(*)::integer
    into v_match_count
  from atlas.farms f
  where f.stable_key = 'elm_farm'
    and f.status = 'active';

  if v_match_count <> 1 then
    raise exception 'Expected exactly one active Elm Farm while establishing Flower Operating Knowledge bindings; found %.', v_match_count;
  end if;

  select f.organization_unit_id
    into v_unit_id
  from atlas.farms f
  where f.stable_key = 'elm_farm'
    and f.status = 'active';

  if v_unit_id is null then
    raise exception 'Elm Farm requires organization_unit_id before Flower Operating Knowledge may bind crop identity.';
  end if;

  select count(*)::integer
    into v_match_count
  from atlas.crop_profiles cp
  where cp.stable_key in ('sunflower_teddy', 'celosia_cut_flower');

  if v_match_count <> 2 then
    raise exception 'Expected canonical sunflower_teddy and celosia_cut_flower crop profiles; found %.', v_match_count;
  end if;

  if exists (
    select 1
    from atlas.crop_profiles cp
    where cp.stable_key in ('sunflower_teddy', 'celosia_cut_flower')
      and not (coalesce(cp.metadata->'use_tags', '[]'::jsonb) @> '["cut_flower"]'::jsonb)
  ) then
    raise exception 'Initial Flower Operating Knowledge bindings require crop profiles already classified as cut_flower.';
  end if;

  insert into atlas.flower_operating_knowledge_crop_bindings (
    organization_unit_id, crop_profile_id, category_key, product_key, source_kind, provenance
  )
  select
    v_unit_id,
    cp.id,
    'cut_flower',
    case cp.stable_key
      when 'sunflower_teddy' then 'sunflower'
      when 'celosia_cut_flower' then 'celosia'
    end,
    'canonical_crop_profile_identity',
    jsonb_build_object(
      'source', 'atlas_flower_preparation_operating_knowledge_v2',
      'cropProfileStableKey', cp.stable_key,
      'basis', 'explicit domain binding; no runtime label or alias parsing'
    )
  from atlas.crop_profiles cp
  where cp.stable_key in ('sunflower_teddy', 'celosia_cut_flower');

  get diagnostics v_insert_count = row_count;
  if v_insert_count <> 2 then
    raise exception 'Expected exactly two initial Flower Operating Knowledge crop bindings; inserted %.', v_insert_count;
  end if;
end;
$seed$;

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
  v_farm atlas.farms%rowtype;
  v_existing atlas.flower_preparation_directives%rowtype;
  v_binding atlas.flower_operating_knowledge_crop_bindings%rowtype;
  v_directive_line atlas.flower_preparation_directive_lines%rowtype;
  v_line jsonb;
  v_line_provenance jsonb;
  v_provenance_item jsonb;
  v_normalized_lines jsonb := '[]'::jsonb;
  v_provenance jsonb := '[]'::jsonb;
  v_context jsonb;
  v_resolution jsonb;
  v_effect jsonb;
  v_rule_ids_json jsonb;
  v_rule_ids uuid[];
  v_result jsonb;
  v_output_kind text;
  v_stems_text text;
  v_stems_per_unit integer;
  v_crop_profile_id uuid;
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_request_fingerprint text;
  v_existing_provenance_count integer;
  v_existing_fingerprint_min text;
  v_existing_fingerprint_max text;
  v_worker_task_id uuid;
  v_line_number integer := 0;
  v_default_count integer := 0;
  v_directive_id uuid;
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
  where id = p_owner_review_task_id;

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

  select * into v_farm
  from atlas.farms
  where id = v_task.farm_id;

  if v_farm.id is null
     or v_farm.organization_id is null
     or v_farm.organization_unit_id is null then
    raise exception 'Flower Preparation requires canonical Organization and Organization Unit custody.' using errcode = '22023';
  end if;

  if not atlas.is_organization_member(v_farm.organization_id) then
    raise exception 'Organization membership is required to apply Company Operating Knowledge.' using errcode = '42501';
  end if;

  v_request_fingerprint := md5(
    p_owner_review_task_id::text || '|' || p_lines::text || '|' || coalesce(v_note, '')
  );

  -- v2 owns idempotency over the original Owner request. The delegated v1
  -- fingerprint is intentionally based on the normalized request, so retries must
  -- short-circuit here before a later rule change could alter normalization.
  select * into v_existing
  from atlas.flower_preparation_directives
  where farm_id = v_task.farm_id
    and idempotency_key = v_key;

  if v_existing.id is not null then
    if v_existing.owner_review_task_id is distinct from p_owner_review_task_id then
      raise exception 'Directive idempotency key was already used for a different Owner review.' using errcode = '22023';
    end if;

    select count(*)::integer, min(p.request_fingerprint), max(p.request_fingerprint)
      into v_existing_provenance_count, v_existing_fingerprint_min, v_existing_fingerprint_max
    from atlas.flower_preparation_directive_line_knowledge_provenance p
    where p.directive_id = v_existing.id;

    if v_existing_provenance_count = 0 then
      raise exception 'Directive idempotency key already belongs to a non-v2 Flower Preparation directive.' using errcode = '22023';
    end if;

    if v_existing_fingerprint_min is distinct from v_request_fingerprint
       or v_existing_fingerprint_max is distinct from v_request_fingerprint then
      raise exception 'Directive idempotency key was already used for a different v2 request.' using errcode = '22023';
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
      'preparationDirectiveVersion', 2,
      'knowledgeProvenanceCount', v_existing_provenance_count,
      'deduplicated', true
    );
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_line_number := v_line_number + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Each preparation direction must be an object.' using errcode = '22023';
    end if;

    v_output_kind := lower(btrim(coalesce(v_line->>'outputKind', '')));
    v_stems_text := btrim(coalesce(v_line->>'stemsPerUnit', ''));
    v_binding := null;
    v_context := '{}'::jsonb;
    v_effect := null;
    v_rule_ids_json := '[]'::jsonb;

    if v_output_kind = 'bundle' and v_stems_text = '' then
      begin
        v_crop_profile_id := nullif(btrim(coalesce(v_line->>'cropProfileId', '')), '')::uuid;
      exception when invalid_text_representation then
        raise exception 'Preparation cropProfileId must be a valid UUID before Operating Knowledge can supply bundle size.' using errcode = '22023';
      end;

      if v_crop_profile_id is null then
        raise exception 'Bundle size was omitted, but no canonical cropProfileId was supplied. Provide stemsPerUnit explicitly.' using errcode = '22023';
      end if;

      select * into v_binding
      from atlas.flower_operating_knowledge_crop_bindings b
      where b.organization_unit_id = v_farm.organization_unit_id
        and b.crop_profile_id = v_crop_profile_id;

      if v_binding.id is null then
        raise exception 'Bundle size was omitted, but crop profile % has no governed Flower Operating Knowledge binding. Provide stemsPerUnit explicitly or establish the binding first.', v_crop_profile_id
          using errcode = '22023';
      end if;

      v_context := jsonb_build_object(
        'organization_unit_id', v_farm.organization_unit_id,
        'operation', 'bunch',
        'category', v_binding.category_key,
        'product', v_binding.product_key
      );

      v_resolution := atlas.resolve_company_operating_knowledge_v1(
        v_farm.organization_id,
        'standard',
        v_context,
        now()
      );

      if coalesce(v_resolution->>'resolution_state', '') <> 'resolved' then
        raise exception 'Flower bundle Operating Knowledge did not resolve deterministically for crop profile % (state=%). Provide stemsPerUnit explicitly.',
          v_crop_profile_id, coalesce(v_resolution->>'resolution_state', 'missing')
          using errcode = '22023';
      end if;

      v_effect := v_resolution->'resolved_effect';
      if coalesce(v_effect->>'sales_unit', '') <> 'bunch'
         or coalesce(v_effect->>'quantity_unit', '') <> 'stem'
         or coalesce(v_effect->>'quantity_per_unit', '') !~ '^[0-9]+$' then
        raise exception 'Resolved Flower bunching Operating Knowledge has an invalid effect contract.' using errcode = '22023';
      end if;

      v_stems_per_unit := (v_effect->>'quantity_per_unit')::integer;
      if v_stems_per_unit < 1 or v_stems_per_unit > 1000 then
        raise exception 'Resolved Flower bunch size must be between 1 and 1000 stems.' using errcode = '22023';
      end if;

      select coalesce(jsonb_agg(value->>'id'), '[]'::jsonb)
        into v_rule_ids_json
      from jsonb_array_elements(coalesce(v_resolution->'matches', '[]'::jsonb));

      if jsonb_array_length(v_rule_ids_json) < 1 then
        raise exception 'Resolved Flower bunching Operating Knowledge did not preserve its rule identity.' using errcode = '22023';
      end if;

      v_line := jsonb_set(v_line, '{stemsPerUnit}', to_jsonb(v_stems_per_unit), true);
      v_default_count := v_default_count + 1;
      v_line_provenance := jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'operating_knowledge',
        'bindingId', v_binding.id,
        'ruleIds', v_rule_ids_json,
        'context', v_context,
        'resolvedEffect', v_effect
      );
    elsif v_output_kind = 'bundle' then
      v_line_provenance := jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'owner_explicit',
        'ruleIds', '[]'::jsonb,
        'context', '{}'::jsonb
      );
    else
      v_line_provenance := jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'not_applicable',
        'ruleIds', '[]'::jsonb,
        'context', '{}'::jsonb
      );
    end if;

    v_normalized_lines := v_normalized_lines || jsonb_build_array(v_line);
    v_provenance := v_provenance || jsonb_build_array(v_line_provenance);
  end loop;

  -- All release authority remains in unchanged v1. If any ordinary v1 invariant
  -- fails, the entire v2 transaction (including provenance) rolls back.
  v_result := atlas.record_flower_preparation_directive_v1(
    p_owner_review_task_id,
    v_normalized_lines,
    p_note,
    p_idempotency_key
  );

  begin
    v_directive_id := nullif(v_result->>'directiveId', '')::uuid;
  exception when invalid_text_representation then
    v_directive_id := null;
  end;

  if v_directive_id is null then
    raise exception 'Flower Preparation v1 did not return a directive identity; v2 transaction was rolled back.' using errcode = 'P0001';
  end if;

  for v_provenance_item in select value from jsonb_array_elements(v_provenance) loop
    select * into v_directive_line
    from atlas.flower_preparation_directive_lines l
    where l.directive_id = v_directive_id
      and l.line_number = (v_provenance_item->>'lineNumber')::integer;

    if v_directive_line.id is null then
      raise exception 'Flower Preparation v2 could not reconcile directive line provenance; transaction was rolled back.' using errcode = 'P0001';
    end if;

    select coalesce(array_agg(value::uuid), '{}'::uuid[])
      into v_rule_ids
    from jsonb_array_elements_text(coalesce(v_provenance_item->'ruleIds', '[]'::jsonb));

    insert into atlas.flower_preparation_directive_line_knowledge_provenance (
      farm_id, directive_id, directive_line_id, line_number, source_kind,
      organization_id, organization_unit_id, binding_id, knowledge_rule_ids,
      resolution_context, resolved_effect, applied_stems_per_unit,
      request_fingerprint
    ) values (
      v_task.farm_id,
      v_directive_id,
      v_directive_line.id,
      v_directive_line.line_number,
      v_provenance_item->>'sourceKind',
      v_farm.organization_id,
      v_farm.organization_unit_id,
      nullif(v_provenance_item->>'bindingId', '')::uuid,
      v_rule_ids,
      coalesce(v_provenance_item->'context', '{}'::jsonb),
      v_provenance_item->'resolvedEffect',
      v_directive_line.stems_per_unit,
      v_request_fingerprint
    );
  end loop;

  return v_result || jsonb_build_object(
    'preparationDirectiveVersion', 2,
    'operatingKnowledgeDefaultCount', v_default_count,
    'knowledgeProvenanceCount', jsonb_array_length(v_provenance)
  );
end;
$function$;

revoke all on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)
  from public, anon, service_role;
grant execute on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)
  to authenticated;

comment on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text) is
  'Owner/manager Flower Preparation directive v2. Explicit stemsPerUnit remains sovereign; only an omitted bundle size with governed crop identity may resolve from established Company Operating Knowledge. Delegates final directive/release authority to unchanged v1 and records immutable source provenance.';

-- Keep the authenticated RPC registry honest for the new app endpoint.
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
  signature, classification, confidence, review_status,
  authenticated_execute_expected, anonymous_execute_expected,
  security_definer_expected, service_execute_expected,
  caller_count, policy_reference_count, evidence, registered_at, reviewed_at
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
    'source', 'atlas_flower_preparation_operating_knowledge_v2',
    'reason', 'owner_explicit_or_governed_operating_knowledge_bundle_size',
    'functionOid', oid,
    'classificationRuleVersion', 3,
    'truthBoundary', 'v2 may default only omitted bundle size from deterministic established Operating Knowledge; unchanged v1 remains directive and continuation-release authority.'
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

commit;
