begin;

create or replace function atlas.record_implementation_compute_usage_service_v1(
  p_artifact_id uuid,
  p_provider_key text,
  p_model_key text,
  p_operation_kind text,
  p_status text,
  p_provider_request_id text default null,
  p_audio_seconds numeric default null,
  p_input_tokens bigint default null,
  p_output_tokens bigint default null,
  p_total_tokens bigint default null,
  p_cached_input_tokens bigint default null,
  p_http_status integer default null,
  p_rate_limit_limit_requests bigint default null,
  p_rate_limit_remaining_requests bigint default null,
  p_rate_limit_limit_tokens bigint default null,
  p_rate_limit_remaining_tokens bigint default null,
  p_rate_limit_reset_requests text default null,
  p_rate_limit_reset_tokens text default null,
  p_retry_after_seconds numeric default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_artifact atlas.implementation_artifacts%rowtype;
begin
  select a.* into v_artifact
  from atlas.implementation_artifacts a
  where a.id=p_artifact_id;

  if v_artifact.id is null then
    raise exception 'Implementation artifact not found.' using errcode='23503';
  end if;

  return atlas.record_external_compute_usage_service_v1(
    p_provider_key => p_provider_key,
    p_model_key => p_model_key,
    p_operation_kind => p_operation_kind,
    p_status => p_status,
    p_implementation_case_id => v_artifact.implementation_case_id,
    p_implementation_artifact_id => v_artifact.id,
    p_attributed_user_id => v_artifact.submitted_by_user_id,
    p_provider_request_id => p_provider_request_id,
    p_audio_seconds => p_audio_seconds,
    p_input_tokens => p_input_tokens,
    p_output_tokens => p_output_tokens,
    p_total_tokens => p_total_tokens,
    p_cached_input_tokens => p_cached_input_tokens,
    p_http_status => p_http_status,
    p_rate_limit_limit_requests => p_rate_limit_limit_requests,
    p_rate_limit_remaining_requests => p_rate_limit_remaining_requests,
    p_rate_limit_limit_tokens => p_rate_limit_limit_tokens,
    p_rate_limit_remaining_tokens => p_rate_limit_remaining_tokens,
    p_rate_limit_reset_requests => p_rate_limit_reset_requests,
    p_rate_limit_reset_tokens => p_rate_limit_reset_tokens,
    p_retry_after_seconds => p_retry_after_seconds,
    p_metadata => p_metadata
  );
end;
$function$;

revoke all on function atlas.record_implementation_compute_usage_service_v1(uuid,text,text,text,text,text,numeric,bigint,bigint,bigint,bigint,integer,bigint,bigint,bigint,bigint,text,text,numeric,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_implementation_compute_usage_service_v1(uuid,text,text,text,text,text,numeric,bigint,bigint,bigint,bigint,integer,bigint,bigint,bigint,bigint,text,text,numeric,jsonb) to service_role;

commit;
