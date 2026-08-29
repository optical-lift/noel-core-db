create table wnph.publication_source_reconstruction_jobs (
  id uuid primary key default gen_random_uuid(),
  job_key text not null unique,
  source_package_id uuid not null references wnph.publication_source_packages(id),
  target_parent_block_id uuid not null references wnph.publication_source_blocks(id),
  asset_keys text[],
  proposed_reading_state text not null default 'candidate' check (proposed_reading_state in ('candidate','usable')),
  allow_usable_auto_admit boolean not null default false,
  proposed_block_key_prefix text,
  start_ordinal integer check (start_ordinal is null or start_ordinal > 0),
  requested_reconstruction_key text,
  request_authority text not null,
  request_reason text not null,
  request_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(request_metadata)='object'),
  priority integer not null default 100,
  status text not null default 'queued' check (status in ('queued','leased','succeeded','failed','cancelled')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  next_attempt_at timestamptz not null default now(),
  leased_by text,
  lease_token uuid,
  lease_expires_at timestamptz,
  final_reconstruction_key text,
  final_stats jsonb,
  final_database_result jsonb,
  final_response jsonb,
  last_error text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table wnph.publication_source_reconstruction_job_attempts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references wnph.publication_source_reconstruction_jobs(id) on delete restrict,
  attempt_number integer not null check (attempt_number > 0),
  runner_id text not null,
  lease_token uuid not null,
  claimed_at timestamptz not null default now(),
  lease_expires_at timestamptz not null,
  finished_at timestamptz,
  outcome text not null default 'running' check (outcome in ('running','succeeded','retry','failed','lease_expired')),
  http_status integer,
  reconstruction_key text,
  stats jsonb,
  database_result jsonb,
  response jsonb,
  error_text text,
  created_at timestamptz not null default now(),
  unique(job_id,attempt_number)
);

create index publication_source_reconstruction_jobs_queue_idx
  on wnph.publication_source_reconstruction_jobs(status,next_attempt_at,priority,created_at)
  where status in ('queued','leased');

create index publication_source_reconstruction_job_attempts_job_idx
  on wnph.publication_source_reconstruction_job_attempts(job_id,attempt_number desc);

alter table wnph.publication_source_reconstruction_jobs enable row level security;
alter table wnph.publication_source_reconstruction_job_attempts enable row level security;

revoke all on table wnph.publication_source_reconstruction_jobs from public,anon,authenticated;
revoke all on table wnph.publication_source_reconstruction_job_attempts from public,anon,authenticated;
grant select on table wnph.publication_source_reconstruction_jobs to service_role;
grant select on table wnph.publication_source_reconstruction_job_attempts to service_role;

comment on table wnph.publication_source_reconstruction_jobs is
'Durable WNPH execution ledger for machine reading reconstruction. A job requests execution against already-governed source custody; it does not itself verify or canonize reconstructed text.';
comment on table wnph.publication_source_reconstruction_job_attempts is
'Attempt ledger for WNPH reconstruction jobs. Leases make worker retries explicit and prevent transport failure from erasing execution history.';

create or replace function public.wnph_request_reconstruction_job_v1(
  p_source_package_key text,
  p_target_parent_block_key text,
  p_job_key text,
  p_request_authority text,
  p_request_reason text,
  p_asset_keys text[] default null,
  p_proposed_reading_state text default 'candidate',
  p_allow_usable_auto_admit boolean default false,
  p_proposed_block_key_prefix text default null,
  p_start_ordinal integer default null,
  p_reconstruction_key text default null,
  p_request_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_pkg wnph.publication_source_packages%rowtype;
  v_parent wnph.publication_source_blocks%rowtype;
  v_existing wnph.publication_source_reconstruction_jobs%rowtype;
  v_job wnph.publication_source_reconstruction_jobs%rowtype;
begin
  if coalesce(btrim(p_source_package_key),'')='' or coalesce(btrim(p_target_parent_block_key),'')='' then
    raise exception 'WNPH reconstruction job requires source package and target parent block keys' using errcode='22023';
  end if;
  if coalesce(btrim(p_job_key),'')='' or coalesce(btrim(p_request_authority),'')='' or coalesce(btrim(p_request_reason),'')='' then
    raise exception 'WNPH reconstruction job requires job key, request authority, and request reason' using errcode='22023';
  end if;
  if p_proposed_reading_state not in ('candidate','usable') then
    raise exception 'WNPH reconstruction job reading state must be candidate or usable' using errcode='22023';
  end if;
  if p_start_ordinal is not null and p_start_ordinal < 1 then
    raise exception 'WNPH reconstruction job start ordinal must be positive' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_request_metadata,'{}'::jsonb))<>'object' then
    raise exception 'WNPH reconstruction job metadata must be an object' using errcode='22023';
  end if;

  select p.* into v_pkg
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id)
  order by p.created_at desc
  limit 1;
  if v_pkg.id is null then
    raise exception 'WNPH reconstruction job active source package not found: %',p_source_package_key using errcode='P0002';
  end if;

  select b.* into v_parent
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg.id
    and b.block_key=p_target_parent_block_key
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)
  order by b.created_at desc
  limit 1;
  if v_parent.id is null then
    raise exception 'WNPH reconstruction job active target parent block not found in source package: %',p_target_parent_block_key using errcode='P0002';
  end if;

  if v_parent.semantic_role='paragraph_stream' and not exists(
    select 1
    from wnph.publication_source_block_spans s
    where s.source_package_id=v_pkg.id
      and s.block_id=v_parent.id
      and not exists(select 1 from wnph.publication_source_block_spans c where c.supersedes_span_id=s.id)
  ) then
    raise exception 'WNPH reconstruction job paragraph stream requires an active governed semantic source span' using errcode='23514';
  end if;

  select j.* into v_existing
  from wnph.publication_source_reconstruction_jobs j
  where j.job_key=p_job_key;

  if v_existing.id is not null then
    if v_existing.source_package_id is distinct from v_pkg.id
       or v_existing.target_parent_block_id is distinct from v_parent.id
       or v_existing.asset_keys is distinct from p_asset_keys
       or v_existing.proposed_reading_state is distinct from p_proposed_reading_state
       or v_existing.allow_usable_auto_admit is distinct from p_allow_usable_auto_admit
       or v_existing.proposed_block_key_prefix is distinct from nullif(btrim(coalesce(p_proposed_block_key_prefix,'')),'')
       or v_existing.start_ordinal is distinct from p_start_ordinal
       or v_existing.requested_reconstruction_key is distinct from nullif(btrim(coalesce(p_reconstruction_key,'')),'')
       or v_existing.request_authority is distinct from btrim(p_request_authority)
       or v_existing.request_reason is distinct from btrim(p_request_reason)
       or v_existing.request_metadata is distinct from coalesce(p_request_metadata,'{}'::jsonb) then
      raise exception 'WNPH reconstruction job key already exists with different request semantics: %',p_job_key using errcode='23505';
    end if;
    return jsonb_build_object(
      'job_id',v_existing.id,
      'job_key',v_existing.job_key,
      'status',v_existing.status,
      'attempt_count',v_existing.attempt_count,
      'deduplicated',true
    );
  end if;

  insert into wnph.publication_source_reconstruction_jobs(
    job_key,source_package_id,target_parent_block_id,asset_keys,proposed_reading_state,
    allow_usable_auto_admit,proposed_block_key_prefix,start_ordinal,requested_reconstruction_key,
    request_authority,request_reason,request_metadata
  ) values (
    btrim(p_job_key),v_pkg.id,v_parent.id,p_asset_keys,p_proposed_reading_state,
    p_allow_usable_auto_admit,nullif(btrim(coalesce(p_proposed_block_key_prefix,'')),''),p_start_ordinal,
    nullif(btrim(coalesce(p_reconstruction_key,'')),''),btrim(p_request_authority),btrim(p_request_reason),
    coalesce(p_request_metadata,'{}'::jsonb)
  ) returning * into v_job;

  return jsonb_build_object(
    'job_id',v_job.id,
    'job_key',v_job.job_key,
    'status',v_job.status,
    'attempt_count',v_job.attempt_count,
    'deduplicated',false
  );
end;
$function$;

create or replace function public.wnph_validate_reconstruction_runner_token_v1(p_token text)
returns boolean
language sql
security definer
stable
set search_path to 'pg_catalog','public','vault','extensions'
as $function$
  select coalesce((
    select extensions.digest(convert_to(coalesce(p_token,''),'UTF8'),'sha256') =
           extensions.digest(convert_to(ds.decrypted_secret,'UTF8'),'sha256')
    from vault.decrypted_secrets ds
    where ds.name='wnph_reconstruction_runner_token_v1'
    order by ds.created_at desc
    limit 1
  ),false);
$function$;

create or replace function public.wnph_claim_reconstruction_job_v1(
  p_runner_id text,
  p_lease_seconds integer default 240
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_job wnph.publication_source_reconstruction_jobs%rowtype;
  v_attempt wnph.publication_source_reconstruction_job_attempts%rowtype;
  v_pkg_key text;
  v_parent_key text;
  v_attempt_number integer;
  v_lease_token uuid;
  v_lease_expires timestamptz;
begin
  if coalesce(btrim(p_runner_id),'')='' then
    raise exception 'WNPH reconstruction claim requires runner id' using errcode='22023';
  end if;
  if p_lease_seconds < 60 or p_lease_seconds > 900 then
    raise exception 'WNPH reconstruction lease must be between 60 and 900 seconds' using errcode='22023';
  end if;

  update wnph.publication_source_reconstruction_job_attempts a
  set outcome='lease_expired',
      finished_at=coalesce(a.finished_at,now()),
      error_text=coalesce(a.error_text,'Worker lease expired before an explicit completion result.')
  where a.outcome='running' and a.lease_expires_at<=now();

  update wnph.publication_source_reconstruction_jobs j
  set status='failed',
      completed_at=coalesce(j.completed_at,now()),
      last_error=coalesce(j.last_error,'Reconstruction worker lease expired after maximum attempts.'),
      leased_by=null,lease_token=null,lease_expires_at=null,updated_at=now()
  where j.status='leased' and j.lease_expires_at<=now() and j.attempt_count>=j.max_attempts;

  select j.* into v_job
  from wnph.publication_source_reconstruction_jobs j
  where j.attempt_count<j.max_attempts
    and (
      (j.status='queued' and j.next_attempt_at<=now())
      or (j.status='leased' and j.lease_expires_at<=now())
    )
  order by j.priority asc,j.created_at asc
  for update skip locked
  limit 1;

  if v_job.id is null then
    return null;
  end if;

  select p.canonical_key into v_pkg_key
  from wnph.publication_source_packages p
  where p.id=v_job.source_package_id
    and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id);
  select b.block_key into v_parent_key
  from wnph.publication_source_blocks b
  where b.id=v_job.target_parent_block_id
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
  if v_pkg_key is null or v_parent_key is null then
    update wnph.publication_source_reconstruction_jobs
    set status='failed',completed_at=now(),last_error='Source package or target parent block ceased to be active before execution.',updated_at=now()
    where id=v_job.id;
    return null;
  end if;

  v_attempt_number:=v_job.attempt_count+1;
  v_lease_token:=gen_random_uuid();
  v_lease_expires:=now()+make_interval(secs=>p_lease_seconds);

  insert into wnph.publication_source_reconstruction_job_attempts(
    job_id,attempt_number,runner_id,lease_token,lease_expires_at
  ) values (
    v_job.id,v_attempt_number,btrim(p_runner_id),v_lease_token,v_lease_expires
  ) returning * into v_attempt;

  update wnph.publication_source_reconstruction_jobs
  set status='leased',attempt_count=v_attempt_number,leased_by=btrim(p_runner_id),lease_token=v_lease_token,
      lease_expires_at=v_lease_expires,updated_at=now()
  where id=v_job.id;

  return jsonb_build_object(
    'job_id',v_job.id,
    'attempt_id',v_attempt.id,
    'lease_token',v_lease_token,
    'source_package_key',v_pkg_key,
    'target_parent_block_key',v_parent_key,
    'asset_keys',to_jsonb(v_job.asset_keys),
    'proposed_reading_state',v_job.proposed_reading_state,
    'allow_usable_auto_admit',v_job.allow_usable_auto_admit,
    'proposed_block_key_prefix',v_job.proposed_block_key_prefix,
    'start_ordinal',v_job.start_ordinal,
    'requested_reconstruction_key',v_job.requested_reconstruction_key
  );
end;
$function$;

create or replace function public.wnph_finish_reconstruction_job_v1(
  p_job_id uuid,
  p_attempt_id uuid,
  p_lease_token uuid,
  p_success boolean,
  p_retryable boolean,
  p_http_status integer,
  p_response jsonb,
  p_error text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_job wnph.publication_source_reconstruction_jobs%rowtype;
  v_attempt wnph.publication_source_reconstruction_job_attempts%rowtype;
  v_retry boolean;
  v_next_attempt timestamptz;
  v_status text;
  v_reconstruction_key text;
  v_stats jsonb;
  v_database jsonb;
begin
  select * into v_job from wnph.publication_source_reconstruction_jobs where id=p_job_id for update;
  if v_job.id is null then raise exception 'WNPH reconstruction job not found' using errcode='P0002'; end if;
  select * into v_attempt from wnph.publication_source_reconstruction_job_attempts where id=p_attempt_id and job_id=p_job_id for update;
  if v_attempt.id is null then raise exception 'WNPH reconstruction attempt not found' using errcode='P0002'; end if;
  if v_attempt.outcome<>'running' or v_job.status<>'leased' or v_job.lease_token is distinct from p_lease_token or v_attempt.lease_token is distinct from p_lease_token then
    raise exception 'WNPH reconstruction completion does not own the active lease' using errcode='40001';
  end if;
  if jsonb_typeof(coalesce(p_response,'{}'::jsonb))<>'object' then
    raise exception 'WNPH reconstruction completion response must be an object' using errcode='22023';
  end if;

  v_reconstruction_key:=nullif(coalesce(p_response->>'reconstruction_key',''),'');
  v_stats:=coalesce(p_response->'stats','{}'::jsonb);
  v_database:=coalesce(p_response->'database','{}'::jsonb);

  if p_success then
    update wnph.publication_source_reconstruction_job_attempts
    set outcome='succeeded',finished_at=now(),http_status=p_http_status,reconstruction_key=v_reconstruction_key,
        stats=v_stats,database_result=v_database,response=coalesce(p_response,'{}'::jsonb),error_text=null
    where id=v_attempt.id;

    update wnph.publication_source_reconstruction_jobs
    set status='succeeded',final_reconstruction_key=v_reconstruction_key,final_stats=v_stats,
        final_database_result=v_database,final_response=coalesce(p_response,'{}'::jsonb),last_error=null,
        completed_at=now(),leased_by=null,lease_token=null,lease_expires_at=null,updated_at=now()
    where id=v_job.id;
    v_status:='succeeded';
  else
    v_retry:=coalesce(p_retryable,false) and v_job.attempt_count<v_job.max_attempts;
    v_next_attempt:=now()+case
      when v_job.attempt_count<=1 then interval '30 seconds'
      when v_job.attempt_count=2 then interval '60 seconds'
      else interval '120 seconds'
    end;

    update wnph.publication_source_reconstruction_job_attempts
    set outcome=case when v_retry then 'retry' else 'failed' end,finished_at=now(),http_status=p_http_status,
        reconstruction_key=v_reconstruction_key,stats=v_stats,database_result=v_database,
        response=coalesce(p_response,'{}'::jsonb),error_text=coalesce(nullif(p_error,''),'Reconstruction worker failed without an error message.')
    where id=v_attempt.id;

    update wnph.publication_source_reconstruction_jobs
    set status=case when v_retry then 'queued' else 'failed' end,
        next_attempt_at=case when v_retry then v_next_attempt else next_attempt_at end,
        last_error=coalesce(nullif(p_error,''),'Reconstruction worker failed without an error message.'),
        completed_at=case when v_retry then null else now() end,
        final_response=case when v_retry then final_response else coalesce(p_response,'{}'::jsonb) end,
        leased_by=null,lease_token=null,lease_expires_at=null,updated_at=now()
    where id=v_job.id;
    v_status:=case when v_retry then 'queued' else 'failed' end;
  end if;

  return jsonb_build_object(
    'job_id',v_job.id,
    'attempt_id',v_attempt.id,
    'status',v_status,
    'attempt_count',v_job.attempt_count,
    'max_attempts',v_job.max_attempts,
    'reconstruction_key',v_reconstruction_key
  );
end;
$function$;

revoke all on function public.wnph_request_reconstruction_job_v1(text,text,text,text,text,text[],text,boolean,text,integer,text,jsonb) from public,anon,authenticated;
revoke all on function public.wnph_validate_reconstruction_runner_token_v1(text) from public,anon,authenticated;
revoke all on function public.wnph_claim_reconstruction_job_v1(text,integer) from public,anon,authenticated;
revoke all on function public.wnph_finish_reconstruction_job_v1(uuid,uuid,uuid,boolean,boolean,integer,jsonb,text) from public,anon,authenticated;
grant execute on function public.wnph_request_reconstruction_job_v1(text,text,text,text,text,text[],text,boolean,text,integer,text,jsonb) to service_role;
grant execute on function public.wnph_validate_reconstruction_runner_token_v1(text) to service_role;
grant execute on function public.wnph_claim_reconstruction_job_v1(text,integer) to service_role;
grant execute on function public.wnph_finish_reconstruction_job_v1(uuid,uuid,uuid,boolean,boolean,integer,jsonb,text) to service_role;

comment on function public.wnph_request_reconstruction_job_v1(text,text,text,text,text,text[],text,boolean,text,integer,text,jsonb) is
'Service-role WNPH execution request membrane. Resolves active source custody and target parentage before creating an idempotent reconstruction job.';
comment on function public.wnph_claim_reconstruction_job_v1(text,integer) is
'Service-role worker claim boundary for durable WNPH reconstruction execution. Uses row locks, expiring leases, and an attempt ledger.';
comment on function public.wnph_finish_reconstruction_job_v1(uuid,uuid,uuid,boolean,boolean,integer,jsonb,text) is
'Service-role WNPH job completion boundary. Only the holder of the active lease token may finalize or retry an execution attempt.';

do $secret$
begin
  if not exists(select 1 from vault.secrets where name='wnph_reconstruction_runner_token_v1') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'wnph_reconstruction_runner_token_v1',
      'Opaque internal credential for the WNPH reconstruction Cron-to-Edge runner. Never expose to clients.'
    );
  end if;
end;
$secret$;

select cron.schedule(
  'wnph-reconstruction-runner-v1',
  '30 seconds',
  $cron$
  select net.http_post(
    url:='https://zirqkouammpwxlqfbsvf.supabase.co/functions/v1/wnph-reading-reconstruction-runner',
    body:=jsonb_build_object('max_jobs',1),
    headers:=jsonb_build_object(
      'Content-Type','application/json',
      'x-wnph-runner-token',(
        select decrypted_secret from vault.decrypted_secrets
        where name='wnph_reconstruction_runner_token_v1'
        order by created_at desc limit 1
      )
    ),
    timeout_milliseconds:=60000
  ) as request_id;
  $cron$
);

do $verify$
declare
  v_secret_count integer;
  v_cron_count integer;
  v_job_count integer;
  v_ch2_proposals integer;
  v_ch2_blocks integer;
  v_ch1_paragraphs integer;
begin
  select count(*) into v_secret_count from vault.secrets where name='wnph_reconstruction_runner_token_v1';
  if v_secret_count<>1 then raise exception 'WNPH reconstruction runner expected exactly one Vault credential; got %',v_secret_count; end if;

  select count(*) into v_cron_count from cron.job where jobname='wnph-reconstruction-runner-v1' and active and schedule='30 seconds';
  if v_cron_count<>1 then raise exception 'WNPH reconstruction runner Cron job missing or misconfigured'; end if;

  select count(*) into v_job_count from wnph.publication_source_reconstruction_jobs;
  if v_job_count<>0 then raise exception 'WNPH execution-lane installation unexpectedly created % reconstruction jobs',v_job_count; end if;

  select count(*) into v_ch2_proposals
  from wnph.publication_source_reconstruction_proposals p
  join wnph.publication_source_blocks parent on parent.id=p.target_parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id);

  select count(*) into v_ch2_blocks
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);

  select count(*) into v_ch1_paragraphs
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:1:paragraph-stream'
    and b.block_type='paragraph'
    and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);

  if v_ch2_proposals<>0 or v_ch2_blocks<>0 or v_ch1_paragraphs<>24 then
    raise exception 'WNPH execution-lane installation crossed reading boundary: ch2 proposals %, ch2 blocks %, ch1 paragraphs %',v_ch2_proposals,v_ch2_blocks,v_ch1_paragraphs;
  end if;

  if has_function_privilege('anon','public.wnph_claim_reconstruction_job_v1(text,integer)','EXECUTE')
     or has_function_privilege('authenticated','public.wnph_claim_reconstruction_job_v1(text,integer)','EXECUTE')
     or has_function_privilege('anon','public.wnph_finish_reconstruction_job_v1(uuid,uuid,uuid,boolean,boolean,integer,jsonb,text)','EXECUTE')
     or has_function_privilege('authenticated','public.wnph_finish_reconstruction_job_v1(uuid,uuid,uuid,boolean,boolean,integer,jsonb,text)','EXECUTE') then
    raise exception 'WNPH reconstruction worker RPC privilege membrane is open to client roles';
  end if;
end;
$verify$;