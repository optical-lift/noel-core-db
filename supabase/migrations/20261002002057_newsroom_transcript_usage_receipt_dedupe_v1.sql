create unique index if not exists processing_usage_provider_request_uidx
  on transcript_core.processing_usage_events(processing_job_id, provider, provider_request_id)
  where provider_request_id is not null;

create or replace function public.newsroom_get_transcript_usage(p_recording_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, transcript_core
as $$
declare
  v_workspace_id uuid;
  v_source_asset_id uuid;
  v_result jsonb;
begin
  select workspace_id, source_asset_id into v_workspace_id, v_source_asset_id
  from transcript_core.recordings where id = p_recording_id;
  if v_workspace_id is null then raise exception 'RECORDING_NOT_FOUND'; end if;
  if public.transcript_core_is_workspace_member(v_workspace_id) is not true then raise exception 'WORKSPACE_READ_FORBIDDEN'; end if;

  with job_ids as (
    select id
    from transcript_core.processing_jobs
    where workspace_id = v_workspace_id
      and source_asset_id = v_source_asset_id
      and job_type = 'transcribe_recording'
  ),
  real_receipts as (
    select u.*
    from transcript_core.processing_usage_events u
    join job_ids j on j.id = u.processing_job_id
    where u.provider_request_id is not null
       or not (
         u.metadata ? 'backfillBasis'
         or coalesce(u.metadata->>'basis','') ilike 'backfill%'
       )
  ),
  fallback_jobs as (
    select j.id as processing_job_id
    from job_ids j
    where not exists (select 1 from real_receipts r where r.processing_job_id = j.id)
  ),
  fallback_receipts as (
    select distinct on (u.processing_job_id)
      u.*
    from transcript_core.processing_usage_events u
    join fallback_jobs f on f.processing_job_id = u.processing_job_id
    order by u.processing_job_id,
      (u.estimated_paid_equivalent_usd is not null) desc,
      u.created_at asc
  ),
  chosen as (
    select * from real_receipts
    union all
    select * from fallback_receipts
  )
  select jsonb_build_object(
    'audioSeconds', coalesce(sum(c.audio_seconds), 0),
    'requestCount', coalesce(sum(c.request_count), 0),
    'estimatedPaidEquivalentUsd', coalesce(sum(c.estimated_paid_equivalent_usd), 0),
    'providers', coalesce(jsonb_agg(distinct jsonb_build_object('provider', c.provider, 'model', c.provider_model)) filter (where c.id is not null), '[]'::jsonb),
    'latestAt', max(c.created_at)
  ) into v_result
  from chosen c;

  return coalesce(v_result, jsonb_build_object('audioSeconds',0,'requestCount',0,'estimatedPaidEquivalentUsd',0,'providers','[]'::jsonb,'latestAt',null));
end;
$$;

grant execute on function public.newsroom_get_transcript_usage(uuid) to authenticated;
revoke all on function public.newsroom_get_transcript_usage(uuid) from anon;