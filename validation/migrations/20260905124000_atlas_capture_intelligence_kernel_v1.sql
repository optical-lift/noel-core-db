-- Validation: Atlas Capture + Intelligence Kernel v1
-- Intended to run after migration 20260905124000_atlas_capture_intelligence_kernel_v1.sql.

DO $validation$
DECLARE
  v_missing text[] := ARRAY[]::text[];
  v_relrowsecurity boolean;
BEGIN
  -- Tables.
  if to_regclass('atlas.capture_observations') is null then v_missing := array_append(v_missing,'atlas.capture_observations'); end if;
  if to_regclass('atlas.capture_interpretation_jobs') is null then v_missing := array_append(v_missing,'atlas.capture_interpretation_jobs'); end if;
  if to_regclass('atlas.reasoning_runs') is null then v_missing := array_append(v_missing,'atlas.reasoning_runs'); end if;
  if to_regclass('atlas.model_inferences') is null then v_missing := array_append(v_missing,'atlas.model_inferences'); end if;
  if to_regclass('atlas.human_adjudications') is null then v_missing := array_append(v_missing,'atlas.human_adjudications'); end if;
  if to_regclass('atlas.human_adjudication_items') is null then v_missing := array_append(v_missing,'atlas.human_adjudication_items'); end if;

  -- Product/server APIs.
  if to_regprocedure('atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb)') is null then v_missing := array_append(v_missing,'capture_text_observation_api_v1'); end if;
  if to_regprocedure('atlas.capture_review_bundle_api_v1(uuid)') is null then v_missing := array_append(v_missing,'capture_review_bundle_api_v1'); end if;
  if to_regprocedure('atlas.capture_adjudicate_api_v1(uuid,uuid,text,jsonb,text)') is null then v_missing := array_append(v_missing,'capture_adjudicate_api_v1'); end if;
  if to_regprocedure('atlas.capture_claim_interpretation_job_api_v1()') is null then v_missing := array_append(v_missing,'capture_claim_interpretation_job_api_v1'); end if;
  if to_regprocedure('atlas.capture_begin_reasoning_run_api_v1(uuid,text,text,text,text,text,text,text,jsonb)') is null then v_missing := array_append(v_missing,'capture_begin_reasoning_run_api_v1'); end if;
  if to_regprocedure('atlas.capture_complete_reasoning_run_api_v1(uuid,jsonb,jsonb,jsonb)') is null then v_missing := array_append(v_missing,'capture_complete_reasoning_run_api_v1'); end if;
  if to_regprocedure('atlas.capture_fail_reasoning_run_api_v1(uuid,text,text,boolean,integer)') is null then v_missing := array_append(v_missing,'capture_fail_reasoning_run_api_v1'); end if;

  if cardinality(v_missing)>0 then
    raise exception 'Atlas capture kernel missing objects: %', array_to_string(v_missing,', ');
  end if;

  -- Critical columns and lineage.
  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='capture_observations' and column_name='client_request_id'
  ) then raise exception 'capture_observations.client_request_id missing'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='capture_observations' and column_name='content_hash'
  ) then raise exception 'capture_observations.content_hash missing'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='reasoning_runs' and column_name='context_manifest'
  ) then raise exception 'reasoning_runs.context_manifest missing'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='model_inferences' and column_name='candidate_payload'
  ) then raise exception 'model_inferences.candidate_payload missing'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='human_adjudication_items' and column_name='presented_payload'
  ) then raise exception 'human_adjudication_items.presented_payload missing'; end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='human_adjudication_items' and column_name='corrected_payload'
  ) then raise exception 'human_adjudication_items.corrected_payload missing'; end if;

  -- RLS defense in depth is enabled on all raw/intelligence tables.
  for v_relrowsecurity in
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in (
        'capture_observations',
        'capture_interpretation_jobs',
        'reasoning_runs',
        'model_inferences',
        'human_adjudications',
        'human_adjudication_items'
      )
  loop
    if not v_relrowsecurity then
      raise exception 'One or more Atlas capture kernel tables has RLS disabled';
    end if;
  end loop;

  if (
    select count(*)
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname in (
        'capture_observations',
        'capture_interpretation_jobs',
        'reasoning_runs',
        'model_inferences',
        'human_adjudications',
        'human_adjudication_items'
      )
      and c.relrowsecurity
  ) <> 6 then
    raise exception 'Expected RLS on all six Atlas capture kernel tables';
  end if;

  -- Authenticated clients are RPC-only: no direct raw-table SELECT/INSERT/UPDATE/DELETE.
  if has_table_privilege('authenticated','atlas.capture_observations','SELECT')
     or has_table_privilege('authenticated','atlas.capture_observations','INSERT')
     or has_table_privilege('authenticated','atlas.capture_observations','UPDATE')
     or has_table_privilege('authenticated','atlas.capture_observations','DELETE') then
    raise exception 'authenticated has unexpected direct privileges on capture_observations';
  end if;

  if has_table_privilege('authenticated','atlas.model_inferences','SELECT')
     or has_table_privilege('authenticated','atlas.human_adjudications','SELECT') then
    raise exception 'authenticated has unexpected direct privileges on inference/adjudication tables';
  end if;

  -- Product functions are intentionally callable by authenticated; worker APIs are not.
  if not has_function_privilege('authenticated','atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb)','EXECUTE') then
    raise exception 'authenticated cannot execute capture_text_observation_api_v1';
  end if;
  if not has_function_privilege('authenticated','atlas.capture_review_bundle_api_v1(uuid)','EXECUTE') then
    raise exception 'authenticated cannot execute capture_review_bundle_api_v1';
  end if;
  if not has_function_privilege('authenticated','atlas.capture_adjudicate_api_v1(uuid,uuid,text,jsonb,text)','EXECUTE') then
    raise exception 'authenticated cannot execute capture_adjudicate_api_v1';
  end if;
  if has_function_privilege('authenticated','atlas.capture_claim_interpretation_job_api_v1()','EXECUTE') then
    raise exception 'authenticated can unexpectedly claim interpretation jobs';
  end if;
  if has_function_privilege('anon','atlas.capture_text_observation_api_v1(text,uuid,text,text,jsonb)','EXECUTE') then
    raise exception 'anon can unexpectedly execute capture API';
  end if;

  -- Append-only lineage triggers.
  if not exists (select 1 from pg_trigger where tgname='capture_observations_append_only' and not tgisinternal) then
    raise exception 'capture_observations append-only trigger missing';
  end if;
  if not exists (select 1 from pg_trigger where tgname='model_inferences_append_only' and not tgisinternal) then
    raise exception 'model_inferences append-only trigger missing';
  end if;
  if not exists (select 1 from pg_trigger where tgname='human_adjudications_append_only' and not tgisinternal) then
    raise exception 'human_adjudications append-only trigger missing';
  end if;
  if not exists (select 1 from pg_trigger where tgname='human_adjudication_items_append_only' and not tgisinternal) then
    raise exception 'human_adjudication_items append-only trigger missing';
  end if;

  -- This release must not invent generic freeform mutation authority.
  if to_regprocedure('atlas.update_any_fact(jsonb)') is not null then
    raise exception 'Forbidden generic update_any_fact mutation exists';
  end if;
  if to_regprocedure('atlas.capture_create_owner_obligation_api_v1(uuid,jsonb)') is not null then
    raise exception 'Domain promotion unexpectedly bundled into capture-kernel migration';
  end if;
END;
$validation$;

select jsonb_build_object(
  'validation','atlas_capture_intelligence_kernel_v1',
  'status','ok',
  'tables',6,
  'authenticated_access','rpc_only',
  'domain_promotion','not_in_this_release'
) as validation_result;
