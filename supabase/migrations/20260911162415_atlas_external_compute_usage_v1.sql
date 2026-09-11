begin;

create table atlas.external_compute_usage_events (
  id uuid primary key default gen_random_uuid(),
  provider_key text not null,
  model_key text not null,
  operation_kind text not null,
  status text not null check (status in ('succeeded','failed','rate_limited')),
  implementation_case_id uuid references atlas.implementation_cases(id) on delete set null,
  implementation_artifact_id uuid references atlas.implementation_artifacts(id) on delete set null,
  attributed_user_id uuid,
  attributed_participant_id uuid references atlas.implementation_case_participants(id) on delete set null,
  provider_request_id text,
  audio_seconds numeric(14,3),
  input_tokens bigint,
  output_tokens bigint,
  total_tokens bigint,
  cached_input_tokens bigint,
  http_status integer,
  rate_limit_limit_requests bigint,
  rate_limit_remaining_requests bigint,
  rate_limit_limit_tokens bigint,
  rate_limit_remaining_tokens bigint,
  rate_limit_reset_requests text,
  rate_limit_reset_tokens text,
  retry_after_seconds numeric(14,3),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (char_length(btrim(provider_key)) between 1 and 120),
  check (char_length(btrim(model_key)) between 1 and 240),
  check (char_length(btrim(operation_kind)) between 1 and 120),
  check (audio_seconds is null or audio_seconds >= 0),
  check (input_tokens is null or input_tokens >= 0),
  check (output_tokens is null or output_tokens >= 0),
  check (total_tokens is null or total_tokens >= 0),
  check (cached_input_tokens is null or cached_input_tokens >= 0),
  check (http_status is null or http_status between 100 and 599)
);

create unique index external_compute_usage_provider_request_uidx
  on atlas.external_compute_usage_events(provider_key,provider_request_id,operation_kind)
  where provider_request_id is not null;
create index external_compute_usage_case_time_idx on atlas.external_compute_usage_events(implementation_case_id,occurred_at desc);
create index external_compute_usage_user_time_idx on atlas.external_compute_usage_events(attributed_user_id,occurred_at desc);
create index external_compute_usage_provider_model_time_idx on atlas.external_compute_usage_events(provider_key,model_key,occurred_at desc);

alter table atlas.external_compute_usage_events enable row level security;
revoke all on atlas.external_compute_usage_events from public,anon,authenticated;
grant select,insert on atlas.external_compute_usage_events to service_role;

create table atlas.external_compute_limit_profiles (
  provider_key text not null,
  model_key text not null,
  plan_key text not null,
  daily_request_limit bigint,
  minute_token_limit bigint,
  daily_token_limit bigint,
  hourly_audio_seconds_limit numeric(14,3),
  daily_audio_seconds_limit numeric(14,3),
  effective_from timestamptz not null,
  source_label text not null,
  source_url text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  primary key(provider_key,model_key,plan_key)
);

alter table atlas.external_compute_limit_profiles enable row level security;
revoke all on atlas.external_compute_limit_profiles from public,anon,authenticated;
grant select on atlas.external_compute_limit_profiles to service_role;

insert into atlas.external_compute_limit_profiles(
 provider_key,model_key,plan_key,daily_request_limit,minute_token_limit,daily_token_limit,
 hourly_audio_seconds_limit,daily_audio_seconds_limit,effective_from,source_label,source_url,metadata
) values
('groq','whisper-large-v3-turbo','free_default',2000,null,null,7200,28800,'2026-09-11T00:00:00Z','Groq published Free Plan limits','https://console.groq.com/docs/rate-limits',jsonb_build_object('rateLimitBasis','published_default','note','Exact organization limits may differ; provider response headers remain authoritative where available.')),
('groq','openai/gpt-oss-20b','free_default',1000,8000,200000,null,null,'2026-09-11T00:00:00Z','Groq published Free Plan limits','https://console.groq.com/docs/rate-limits',jsonb_build_object('rateLimitBasis','published_default','note','Exact organization limits may differ; provider response headers remain authoritative where available.'));

create or replace function atlas.record_external_compute_usage_service_v1(
 p_provider_key text,p_model_key text,p_operation_kind text,p_status text,
 p_implementation_case_id uuid default null,p_implementation_artifact_id uuid default null,p_attributed_user_id uuid default null,
 p_provider_request_id text default null,p_audio_seconds numeric default null,p_input_tokens bigint default null,p_output_tokens bigint default null,
 p_total_tokens bigint default null,p_cached_input_tokens bigint default null,p_http_status integer default null,
 p_rate_limit_limit_requests bigint default null,p_rate_limit_remaining_requests bigint default null,
 p_rate_limit_limit_tokens bigint default null,p_rate_limit_remaining_tokens bigint default null,
 p_rate_limit_reset_requests text default null,p_rate_limit_reset_tokens text default null,p_retry_after_seconds numeric default null,
 p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas' as $function$
declare v_id uuid; v_participant_id uuid; v_provider text:=btrim(coalesce(p_provider_key,'')); v_model text:=btrim(coalesce(p_model_key,'')); v_operation text:=btrim(coalesce(p_operation_kind,'')); v_status text:=btrim(coalesce(p_status,''));
begin
 if v_provider='' or v_model='' or v_operation='' then raise exception 'Provider, model, and operation are required.' using errcode='22023'; end if;
 if v_status not in ('succeeded','failed','rate_limited') then raise exception 'Unsupported compute usage status.' using errcode='22023'; end if;
 if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then raise exception 'Metadata must be a JSON object.' using errcode='22023'; end if;
 if p_implementation_case_id is not null and p_attributed_user_id is not null then
  select cp.id into v_participant_id from atlas.implementation_case_participants cp where cp.implementation_case_id=p_implementation_case_id and cp.human_user_id=p_attributed_user_id and cp.active and cp.ended_at is null order by cp.started_at desc,cp.id limit 1;
 end if;
 insert into atlas.external_compute_usage_events(provider_key,model_key,operation_kind,status,implementation_case_id,implementation_artifact_id,attributed_user_id,attributed_participant_id,provider_request_id,audio_seconds,input_tokens,output_tokens,total_tokens,cached_input_tokens,http_status,rate_limit_limit_requests,rate_limit_remaining_requests,rate_limit_limit_tokens,rate_limit_remaining_tokens,rate_limit_reset_requests,rate_limit_reset_tokens,retry_after_seconds,metadata)
 values(v_provider,v_model,v_operation,v_status,p_implementation_case_id,p_implementation_artifact_id,p_attributed_user_id,v_participant_id,nullif(btrim(coalesce(p_provider_request_id,'')),''),p_audio_seconds,p_input_tokens,p_output_tokens,p_total_tokens,p_cached_input_tokens,p_http_status,p_rate_limit_limit_requests,p_rate_limit_remaining_requests,p_rate_limit_limit_tokens,p_rate_limit_remaining_tokens,nullif(btrim(coalesce(p_rate_limit_reset_requests,'')),''),nullif(btrim(coalesce(p_rate_limit_reset_tokens,'')),''),p_retry_after_seconds,p_metadata)
 on conflict(provider_key,provider_request_id,operation_kind) where provider_request_id is not null do update set status=excluded.status,audio_seconds=coalesce(excluded.audio_seconds,atlas.external_compute_usage_events.audio_seconds),input_tokens=coalesce(excluded.input_tokens,atlas.external_compute_usage_events.input_tokens),output_tokens=coalesce(excluded.output_tokens,atlas.external_compute_usage_events.output_tokens),total_tokens=coalesce(excluded.total_tokens,atlas.external_compute_usage_events.total_tokens),cached_input_tokens=coalesce(excluded.cached_input_tokens,atlas.external_compute_usage_events.cached_input_tokens),http_status=coalesce(excluded.http_status,atlas.external_compute_usage_events.http_status),rate_limit_limit_requests=coalesce(excluded.rate_limit_limit_requests,atlas.external_compute_usage_events.rate_limit_limit_requests),rate_limit_remaining_requests=coalesce(excluded.rate_limit_remaining_requests,atlas.external_compute_usage_events.rate_limit_remaining_requests),rate_limit_limit_tokens=coalesce(excluded.rate_limit_limit_tokens,atlas.external_compute_usage_events.rate_limit_limit_tokens),rate_limit_remaining_tokens=coalesce(excluded.rate_limit_remaining_tokens,atlas.external_compute_usage_events.rate_limit_remaining_tokens),rate_limit_reset_requests=coalesce(excluded.rate_limit_reset_requests,atlas.external_compute_usage_events.rate_limit_reset_requests),rate_limit_reset_tokens=coalesce(excluded.rate_limit_reset_tokens,atlas.external_compute_usage_events.rate_limit_reset_tokens),retry_after_seconds=coalesce(excluded.retry_after_seconds,atlas.external_compute_usage_events.retry_after_seconds),metadata=atlas.external_compute_usage_events.metadata||excluded.metadata
 returning id into v_id;
 return jsonb_build_object('ok',true,'usageEventId',v_id);
end;$function$;

revoke all on function atlas.record_external_compute_usage_service_v1(text,text,text,text,uuid,uuid,uuid,text,numeric,bigint,bigint,bigint,bigint,integer,bigint,bigint,bigint,bigint,text,text,numeric,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_external_compute_usage_service_v1(text,text,text,text,uuid,uuid,uuid,text,numeric,bigint,bigint,bigint,bigint,integer,bigint,bigint,bigint,bigint,text,text,numeric,jsonb) to service_role;

create or replace function atlas.implementation_compute_usage_self_api_v1(p_implementation_case_id uuid default null,p_window_days integer default 1)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_since timestamptz; v_voice_limit numeric:=28800; v_text_limit bigint:=200000; v_result jsonb;
begin
 if not atlas.implementation_practitioner_authorized_self_v1() then return jsonb_build_object('ok',false,'code','practitioner_authority_required'); end if;
 if p_window_days is null or p_window_days<1 or p_window_days>90 then raise exception 'Usage window must be between 1 and 90 days.' using errcode='22023'; end if;
 if p_implementation_case_id is not null and not exists(select 1 from atlas.implementation_cases c where c.id=p_implementation_case_id) then raise exception 'Implementation case not found.' using errcode='23503'; end if;
 v_since:=now()-make_interval(days=>p_window_days);
 select coalesce(daily_audio_seconds_limit,28800) into v_voice_limit from atlas.external_compute_limit_profiles where provider_key='groq' and model_key='whisper-large-v3-turbo' and plan_key='free_default';
 select coalesce(daily_token_limit,200000) into v_text_limit from atlas.external_compute_limit_profiles where provider_key='groq' and model_key='openai/gpt-oss-20b' and plan_key='free_default';
 select jsonb_build_object(
 'ok',true,'contractVersion','implementation_compute_usage_self_api_v1','windowDays',p_window_days,'implementationCaseId',p_implementation_case_id,
 'pool',jsonb_build_object(
   'voice',jsonb_build_object('usedAudioSeconds24h',coalesce((select sum(e.audio_seconds) from atlas.external_compute_usage_events e where e.provider_key='groq' and e.model_key='whisper-large-v3-turbo' and e.status='succeeded' and e.occurred_at>=now()-interval '24 hours'),0),'dailyAudioSecondsReference',v_voice_limit,'referenceKind','published_free_default'),
   'interpretation',jsonb_build_object('usedTokens24h',coalesce((select sum(e.total_tokens) from atlas.external_compute_usage_events e where e.provider_key='groq' and e.model_key='openai/gpt-oss-20b' and e.status='succeeded' and e.occurred_at>=now()-interval '24 hours'),0),'dailyTokenReference',v_text_limit,'referenceKind','published_free_default'),
   'latestHeadroom',coalesce((select jsonb_agg(jsonb_build_object('providerKey',x.provider_key,'modelKey',x.model_key,'capturedAt',x.occurred_at,'limitRequests',x.rate_limit_limit_requests,'remainingRequests',x.rate_limit_remaining_requests,'limitTokens',x.rate_limit_limit_tokens,'remainingTokens',x.rate_limit_remaining_tokens,'resetRequests',x.rate_limit_reset_requests,'resetTokens',x.rate_limit_reset_tokens) order by x.model_key) from (select distinct on(e.provider_key,e.model_key) e.* from atlas.external_compute_usage_events e where e.provider_key='groq' order by e.provider_key,e.model_key,e.occurred_at desc,e.id desc)x),'[]'::jsonb)),
 'scope',jsonb_build_object('audioSeconds',coalesce((select sum(e.audio_seconds) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id)),0),'inputTokens',coalesce((select sum(e.input_tokens) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id)),0),'outputTokens',coalesce((select sum(e.output_tokens) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id)),0),'totalTokens',coalesce((select sum(e.total_tokens) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id)),0),'requestCount',(select count(*) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id)),'failedRequestCount',(select count(*) from atlas.external_compute_usage_events e where e.occurred_at>=v_since and e.status<>'succeeded' and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id))),
 'cases',coalesce((select jsonb_agg(jsonb_build_object('implementationCaseId',q.implementation_case_id,'startingLabel',q.starting_label,'organizationName',q.organization_name,'audioSeconds',q.audio_seconds,'inputTokens',q.input_tokens,'outputTokens',q.output_tokens,'totalTokens',q.total_tokens,'requestCount',q.request_count,'lastUsedAt',q.last_used_at) order by q.last_used_at desc nulls last) from (select e.implementation_case_id,p.starting_label,max(o.name) organization_name,coalesce(sum(e.audio_seconds),0) audio_seconds,coalesce(sum(e.input_tokens),0) input_tokens,coalesce(sum(e.output_tokens),0) output_tokens,coalesce(sum(e.total_tokens),0) total_tokens,count(*) request_count,max(e.occurred_at) last_used_at from atlas.external_compute_usage_events e join atlas.implementation_cases c on c.id=e.implementation_case_id join atlas.implementation_purchases p on p.id=c.implementation_purchase_id left join atlas.ledger_entitlement_bindings b on b.implementation_case_id=c.id and b.state<>'ended' left join atlas.organizations o on o.id=b.organization_id where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id) group by e.implementation_case_id,p.starting_label)q),'[]'::jsonb),
 'users',coalesce((select jsonb_agg(jsonb_build_object('userId',q.attributed_user_id,'displayName',q.display_name,'implementationCaseId',q.implementation_case_id,'startingLabel',q.starting_label,'audioSeconds',q.audio_seconds,'totalTokens',q.total_tokens,'requestCount',q.request_count,'lastUsedAt',q.last_used_at) order by q.last_used_at desc nulls last) from (select e.attributed_user_id,e.implementation_case_id,p.starting_label,coalesce(max(up.display_name),max(split_part(au.email,'@',1)),'Unattributed') display_name,coalesce(sum(e.audio_seconds),0) audio_seconds,coalesce(sum(e.total_tokens),0) total_tokens,count(*) request_count,max(e.occurred_at) last_used_at from atlas.external_compute_usage_events e left join atlas.implementation_cases c on c.id=e.implementation_case_id left join atlas.implementation_purchases p on p.id=c.implementation_purchase_id left join atlas.user_profiles up on up.user_id=e.attributed_user_id left join auth.users au on au.id=e.attributed_user_id where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id) group by e.attributed_user_id,e.implementation_case_id,p.starting_label)q),'[]'::jsonb),
 'recentEvents',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'providerKey',r.provider_key,'modelKey',r.model_key,'operationKind',r.operation_kind,'status',r.status,'implementationCaseId',r.implementation_case_id,'userId',r.attributed_user_id,'audioSeconds',r.audio_seconds,'inputTokens',r.input_tokens,'outputTokens',r.output_tokens,'totalTokens',r.total_tokens,'occurredAt',r.occurred_at) order by r.occurred_at desc) from (select e.* from atlas.external_compute_usage_events e where e.occurred_at>=v_since and (p_implementation_case_id is null or e.implementation_case_id=p_implementation_case_id) order by e.occurred_at desc,e.id desc limit 50)r),'[]'::jsonb)
 ) into v_result;
 return v_result;
end;$function$;

revoke all on function atlas.implementation_compute_usage_self_api_v1(uuid,integer) from public,anon;
grant execute on function atlas.implementation_compute_usage_self_api_v1(uuid,integer) to authenticated;

commit;
