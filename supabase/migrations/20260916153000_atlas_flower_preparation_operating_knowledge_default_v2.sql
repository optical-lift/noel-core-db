begin;

-- Operating Knowledge execution proof / Flower Preparation v2.
--
-- Governing boundary:
--   * record_flower_preparation_directive_v1 remains the sole authority that
--     issues the immutable Owner directive, completes Owner review, and releases
--     the waiting Flower Preparation continuation.
--   * v2 may supply a missing bundle size only from one deterministic established
--     Company Operating Knowledge resolution.
--   * explicit Owner stemsPerUnit always wins and never invokes the resolver.
--   * crop identity comes from canonical crop_profile_id / crop_profiles, never
--     from the free-form directive product label when a default is needed.
--   * provenance is immutable and separate from the immutable v1 directive rows.
--
-- This migration is schema/authority only. It creates no Flower, crop, farm,
-- Organization, or Operating Knowledge business/configuration rows.

do $preflight$
begin
  if to_regprocedure('atlas.record_flower_preparation_directive_v1(uuid,jsonb,text,text)') is null then
    raise exception 'Flower Preparation v1 authority is missing.';
  end if;
  if to_regprocedure('atlas.resolve_company_operating_knowledge_v1(uuid,text,jsonb,timestamp with time zone)') is null then
    raise exception 'Company Operating Knowledge resolver authority is missing.';
  end if;
  if to_regprocedure('atlas.is_organization_member(uuid)') is null then
    raise exception 'Organization membership authority is missing.';
  end if;
  if to_regclass('atlas.flower_preparation_directives') is null
     or to_regclass('atlas.flower_preparation_directive_lines') is null
     or to_regclass('atlas.crop_profiles') is null then
    raise exception 'Flower Preparation directive/crop custody is missing.';
  end if;
end
$preflight$;

create table atlas.flower_preparation_directive_line_knowledge_provenance (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete restrict,
  directive_id uuid not null,
  directive_line_id uuid not null references atlas.flower_preparation_directive_lines(id) on delete restrict,
  line_number integer not null,
  source_kind text not null,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid not null references atlas.organization_units(id) on delete restrict,
  crop_profile_id uuid references atlas.crop_profiles(id) on delete restrict,
  product_key text,
  knowledge_rule_ids uuid[] not null default '{}'::uuid[],
  resolution_context jsonb not null default '{}'::jsonb,
  resolved_effect jsonb,
  applied_stems_per_unit integer,
  request_fingerprint text not null,
  created_at timestamptz not null default now(),
  constraint flower_prep_knowledge_provenance_directive_farm_fkey
    foreign key (directive_id, farm_id)
    references atlas.flower_preparation_directives(id, farm_id)
    on delete restrict,
  constraint flower_prep_knowledge_provenance_line_uq unique (directive_line_id),
  constraint flower_prep_knowledge_provenance_number_uq unique (directive_id, line_number),
  constraint flower_prep_knowledge_provenance_line_number_check check (line_number between 1 and 12),
  constraint flower_prep_knowledge_provenance_source_check
    check (source_kind in ('owner_explicit', 'operating_knowledge', 'not_applicable')),
  constraint flower_prep_knowledge_provenance_product_key_check
    check (product_key is null or product_key ~ '^[a-z0-9][a-z0-9_]*$'),
  constraint flower_prep_knowledge_provenance_context_check
    check (jsonb_typeof(resolution_context) = 'object'),
  constraint flower_prep_knowledge_provenance_effect_check
    check (resolved_effect is null or jsonb_typeof(resolved_effect) = 'object'),
  constraint flower_prep_knowledge_provenance_fingerprint_check
    check (request_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint flower_prep_knowledge_provenance_stems_check
    check (applied_stems_per_unit is null or applied_stems_per_unit between 1 and 1000),
  constraint flower_prep_knowledge_provenance_semantics_check
    check (
      (source_kind = 'owner_explicit'
        and cardinality(knowledge_rule_ids) = 0
        and resolved_effect is null
        and applied_stems_per_unit is not null)
      or
      (source_kind = 'operating_knowledge'
        and crop_profile_id is not null
        and product_key is not null
        and cardinality(knowledge_rule_ids) > 0
        and resolved_effect is not null
        and applied_stems_per_unit is not null)
      or
      (source_kind = 'not_applicable'
        and cardinality(knowledge_rule_ids) = 0
        and resolved_effect is null
        and applied_stems_per_unit is null)
    )
);

comment on table atlas.flower_preparation_directive_line_knowledge_provenance is
  'Immutable provenance beside Flower Preparation directive lines. Distinguishes explicit Owner bundle size from an established Operating Knowledge default without changing v1 directive truth.';

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

revoke all on function atlas.prevent_flower_preparation_directive_line_knowledge_provenance_mutation_v1()
  from public, anon, authenticated, service_role;

create trigger flower_prep_knowledge_provenance_immutable_v1
before update or delete on atlas.flower_preparation_directive_line_knowledge_provenance
for each row execute function atlas.prevent_flower_preparation_directive_line_knowledge_provenance_mutation_v1();

alter table atlas.flower_preparation_directive_line_knowledge_provenance enable row level security;
grant select on atlas.flower_preparation_directive_line_knowledge_provenance to authenticated;
grant all on atlas.flower_preparation_directive_line_knowledge_provenance to service_role;

create policy flower_prep_knowledge_provenance_member_read_v1
  on atlas.flower_preparation_directive_line_knowledge_provenance
  for select
  to authenticated
  using (atlas.is_farm_member(farm_id));

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
  v_crop_profile atlas.crop_profiles%rowtype;
  v_directive_line atlas.flower_preparation_directive_lines%rowtype;
  v_line jsonb;
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
  v_product_key text;
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

  -- This is the Owner's original request, before Atlas supplies any default.
  -- It is preserved in provenance so an idempotent retry does not change meaning
  -- merely because Operating Knowledge was versioned later.
  v_request_fingerprint := md5(
    p_owner_review_task_id::text || '|' || p_lines::text || '|' || coalesce(v_note, '')
  );

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
      'operatingKnowledgeDefaultCount', (
        select count(*) from atlas.flower_preparation_directive_line_knowledge_provenance p
        where p.directive_id = v_existing.id and p.source_kind = 'operating_knowledge'
      ),
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
    v_context := '{}'::jsonb;
    v_effect := null;
    v_rule_ids_json := '[]'::jsonb;
    v_crop_profile := null;
    v_crop_profile_id := null;
    v_product_key := null;

    if v_output_kind = 'bundle' and v_stems_text = '' then
      begin
        v_crop_profile_id := nullif(btrim(coalesce(v_line->>'cropProfileId', '')), '')::uuid;
      exception when invalid_text_representation then
        raise exception 'Preparation cropProfileId must be a valid UUID before Operating Knowledge can supply bundle size.' using errcode = '22023';
      end;

      if v_crop_profile_id is null then
        raise exception 'Bundle size was omitted, but no canonical cropProfileId was supplied. Provide stemsPerUnit explicitly.' using errcode = '22023';
      end if;

      select * into v_crop_profile
      from atlas.crop_profiles cp
      where cp.id = v_crop_profile_id;

      if v_crop_profile.id is null then
        raise exception 'Preparation crop profile was not found.' using errcode = '22023';
      end if;

      -- crop_label is canonical crop-profile master data, not the Owner's free-form
      -- directive productLabel. Normalize it only into the resolver's product-key
      -- vocabulary; v1 still proves that the crop profile belongs to this harvest.
      v_product_key := lower(regexp_replace(btrim(v_crop_profile.crop_label), '[^a-z0-9]+', '_', 'g'));
      v_product_key := btrim(v_product_key, '_');

      if v_product_key is null or v_product_key = '' then
        raise exception 'Canonical crop profile does not provide a usable Operating Knowledge product key.' using errcode = '22023';
      end if;

      v_context := jsonb_build_object(
        'organization_unit_id', v_farm.organization_unit_id,
        'operation', 'bunch',
        'category', 'cut_flower',
        'product', v_product_key
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
      v_provenance := v_provenance || jsonb_build_array(jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'operating_knowledge',
        'cropProfileId', v_crop_profile_id,
        'productKey', v_product_key,
        'ruleIds', v_rule_ids_json,
        'context', v_context,
        'resolvedEffect', v_effect
      ));
    elsif v_output_kind = 'bundle' then
      v_provenance := v_provenance || jsonb_build_array(jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'owner_explicit',
        'ruleIds', '[]'::jsonb,
        'context', '{}'::jsonb
      ));
    else
      v_provenance := v_provenance || jsonb_build_array(jsonb_build_object(
        'lineNumber', v_line_number,
        'sourceKind', 'not_applicable',
        'ruleIds', '[]'::jsonb,
        'context', '{}'::jsonb
      ));
    end if;

    v_normalized_lines := v_normalized_lines || jsonb_build_array(v_line);
  end loop;

  -- Final directive/release authority remains in unchanged v1. If any ordinary
  -- v1 invariant fails, this whole v2 transaction, including provenance, rolls back.
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
      raise exception 'Flower Preparation v2 could not reconcile directive-line provenance; transaction was rolled back.' using errcode = 'P0001';
    end if;

    select coalesce(array_agg(value::uuid), '{}'::uuid[])
      into v_rule_ids
    from jsonb_array_elements_text(coalesce(v_provenance_item->'ruleIds', '[]'::jsonb));

    insert into atlas.flower_preparation_directive_line_knowledge_provenance (
      farm_id, directive_id, directive_line_id, line_number, source_kind,
      organization_id, organization_unit_id, crop_profile_id, product_key,
      knowledge_rule_ids, resolution_context, resolved_effect,
      applied_stems_per_unit, request_fingerprint
    ) values (
      v_task.farm_id,
      v_directive_id,
      v_directive_line.id,
      v_directive_line.line_number,
      v_provenance_item->>'sourceKind',
      v_farm.organization_id,
      v_farm.organization_unit_id,
      nullif(v_provenance_item->>'cropProfileId', '')::uuid,
      nullif(v_provenance_item->>'productKey', ''),
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
  from public, anon, authenticated, service_role;
grant execute on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)
  to authenticated;

comment on function atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text) is
  'Owner/manager Flower Preparation v2. Explicit stemsPerUnit remains sovereign; only an omitted bundle size with canonical crop_profile_id may resolve from established Company Operating Knowledge. Delegates final directive/release authority to unchanged v1 and records immutable provenance.';

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
    'truthBoundary', 'Owner explicit preparation remains sovereign. Omitted bundle size may be supplied by deterministic established Operating Knowledge, while final directive/release authority remains in v1.'
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
  v_registry_count integer;
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
     or position('record_flower_preparation_directive_v1' in v_def) = 0
     or position('flower_preparation_directive_line_knowledge_provenance' in v_def) = 0 then
    raise exception 'Flower Preparation v2 is missing its governed resolve -> v1 -> provenance contract.';
  end if;

  select count(*) into v_registry_count
  from atlas.authenticated_rpc_registry r
  where r.signature = 'atlas.record_flower_preparation_directive_v2(uuid, jsonb, text, text)'
    and r.classification = 'app_endpoint'
    and r.review_status = 'active'
    and r.authenticated_execute_expected is true
    and r.anonymous_execute_expected is false
    and r.service_execute_expected is false
    and r.security_definer_expected is true;

  if v_registry_count <> 1 then
    raise exception 'Flower Preparation v2 authenticated RPC registry row is missing or inconsistent.';
  end if;
end
$verification$;

commit;
