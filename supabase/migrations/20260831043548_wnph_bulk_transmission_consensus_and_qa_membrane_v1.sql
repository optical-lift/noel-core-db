create table if not exists wnph.publication_source_bulk_policies (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key)<>''),
  policy_version integer not null check (policy_version>=1),
  status text not null check (status in ('active','retired','experimental')),
  consensus_mode text not null check (consensus_mode in ('normalized_exact')),
  min_processor_families integer not null check (min_processor_families>=2 and min_processor_families<=8),
  min_proposal_confidence numeric not null check (min_proposal_confidence>=0 and min_proposal_confidence<=1),
  qa_sample_rate numeric not null check (qa_sample_rate>0 and qa_sample_rate<=1),
  qa_min_samples integer not null check (qa_min_samples>=1),
  qa_max_samples integer not null check (qa_max_samples>=qa_min_samples),
  max_major_error_rate numeric not null check (max_major_error_rate>=0 and max_major_error_rate<=1),
  risk_rules jsonb not null default '{}'::jsonb check (jsonb_typeof(risk_rules)='object'),
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists wnph.publication_source_bulk_batches (
  id uuid primary key default gen_random_uuid(),
  batch_key text not null unique check (btrim(batch_key)<>''),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  target_parent_block_id uuid not null references wnph.publication_source_blocks(id),
  policy_id uuid not null references wnph.publication_source_bulk_policies(id),
  reconstruction_job_id uuid references wnph.publication_source_reconstruction_jobs(id),
  asset_keys text[] not null check (cardinality(asset_keys)>=1),
  status text not null default 'planned' check (status in ('planned','evidence_ready','queued','running','qa_pending','closed','failed','cancelled')),
  qa_status text not null default 'not_started' check (qa_status in ('not_started','pending','pass','fail')),
  stats jsonb not null default '{}'::jsonb check (jsonb_typeof(stats)='object'),
  notes text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists wnph.publication_source_bulk_qa_samples (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references wnph.publication_source_bulk_batches(id) on delete cascade,
  proposal_id uuid not null references wnph.publication_source_reconstruction_proposals(id),
  publication_source_block_id uuid references wnph.publication_source_blocks(id),
  sample_ordinal integer not null check (sample_ordinal>=1),
  sample_reason text not null check (btrim(sample_reason)<>''),
  outcome text not null default 'pending' check (outcome in ('pending','pass','minor_error','major_error')),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(batch_id,proposal_id),
  unique(batch_id,sample_ordinal)
);

create index if not exists publication_source_bulk_batches_package_idx on wnph.publication_source_bulk_batches(source_package_id,status);
create index if not exists publication_source_bulk_qa_samples_batch_outcome_idx on wnph.publication_source_bulk_qa_samples(batch_id,outcome);

insert into wnph.publication_source_bulk_policies(
  canonical_key,policy_version,status,consensus_mode,min_processor_families,min_proposal_confidence,
  qa_sample_rate,qa_min_samples,qa_max_samples,max_major_error_rate,risk_rules,notes
) values (
  'wnph:bulk-transmission:normalized-exact-consensus:v1',1,'active','normalized_exact',2,0.70,
  0.05,8,30,0,
  jsonb_build_object(
    'auto_admit_requires_empty_risk_flags',true,
    'headings_require_review',true,
    'ambiguous_page_continuity_requires_review',true,
    'illegible_or_unresolved_markers_require_review',true,
    'verified_and_adjudicated_states_remain_forensic_only',true
  ),
  'Library-scale default. Auto-admit to usable only when at least two independent processor families agree after comparison-only normalization. Any substantive disagreement remains review. Statistical QA is mandatory before batch closure.'
) on conflict (canonical_key) do nothing;

create or replace function wnph.normalize_parallel_reading_text_v1(p_text text)
returns text
language sql
immutable
set search_path=pg_catalog,wnph
as $$
  select btrim(regexp_replace(
    lower(translate(coalesce(p_text,''),'ſꝛꝚ','srr')),
    '[^a-z0-9]+',' ','g'
  ));
$$;

create or replace function wnph.validate_publication_source_reconstruction_proposal_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,wnph
as $$
declare
  v_parent_package uuid;
  v_obs_id uuid;
  v_obs_package uuid;
  v_old wnph.publication_source_reconstruction_proposals%rowtype;
  v_distinct_obs integer;
  v_policy wnph.publication_source_bulk_policies%rowtype;
  v_bulk_policy_key text;
  v_consensus_ids uuid[];
  v_consensus_count integer;
  v_processor_families integer;
  v_normalized_readings integer;
  v_nonempty_normalized integer;
  v_risk_flags jsonb;
begin
  if jsonb_typeof(new.review_reasons)<>'array' then
    raise exception 'WNPH reconstruction proposal: review_reasons must be an array';
  end if;
  if jsonb_typeof(new.proposed_properties)<>'object'
     or jsonb_typeof(new.proposed_source_provenance)<>'object'
     or jsonb_typeof(new.algorithm)<>'object' then
    raise exception 'WNPH reconstruction proposal: properties, provenance and algorithm must be objects';
  end if;

  select b.source_package_id into v_parent_package
  from wnph.publication_source_blocks b
  where b.id=new.target_parent_block_id
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);
  if v_parent_package is null or v_parent_package<>new.source_package_id then
    raise exception 'WNPH reconstruction proposal: target parent must be an active block in the same source package';
  end if;

  select count(distinct x) into v_distinct_obs from unnest(new.source_observation_ids) x;
  if v_distinct_obs<>cardinality(new.source_observation_ids) then
    raise exception 'WNPH reconstruction proposal: source_observation_ids may not contain duplicates';
  end if;
  foreach v_obs_id in array new.source_observation_ids loop
    select a.source_package_id into v_obs_package
    from wnph.publication_source_observations o
    join wnph.publication_source_assets a on a.id=o.source_asset_id
    where o.id=v_obs_id
      and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
    if v_obs_package is null or v_obs_package<>new.source_package_id then
      raise exception 'WNPH reconstruction proposal: observation % must be active and belong to the same source package',v_obs_id;
    end if;
  end loop;

  if jsonb_typeof(new.proposed_source_provenance->'source_locators')<>'array'
     or jsonb_array_length(new.proposed_source_provenance->'source_locators')=0 then
    raise exception 'WNPH reconstruction proposal: source_locators are required';
  end if;
  if coalesce(new.proposed_source_provenance->>'text_authority','')='' then
    raise exception 'WNPH reconstruction proposal: text_authority is required';
  end if;
  if coalesce(new.proposed_source_provenance->>'derivation_method','')='' then
    raise exception 'WNPH reconstruction proposal: derivation_method is required';
  end if;
  if coalesce(new.algorithm->>'engine','')='' or coalesce(new.algorithm->>'version','')='' then
    raise exception 'WNPH reconstruction proposal: algorithm requires engine and version';
  end if;

  if new.disposition='auto_admit' then
    if jsonb_array_length(new.review_reasons)<>0 then
      raise exception 'WNPH reconstruction proposal: auto_admit may not carry review reasons';
    end if;
    if coalesce(new.algorithm->>'auto_admit_rule','')='' then
      raise exception 'WNPH reconstruction proposal: auto_admit requires an explicit algorithm auto_admit_rule';
    end if;
  elsif new.disposition='review' then
    if jsonb_array_length(new.review_reasons)=0 then
      raise exception 'WNPH reconstruction proposal: review disposition requires at least one review reason';
    end if;
  end if;

  v_bulk_policy_key:=nullif(new.proposed_source_provenance->>'bulk_policy_key','');
  if v_bulk_policy_key is not null then
    select * into v_policy from wnph.publication_source_bulk_policies
    where canonical_key=v_bulk_policy_key and status='active';
    if v_policy.id is null then
      raise exception 'WNPH bulk reconstruction: active policy % not found',v_bulk_policy_key;
    end if;
    if jsonb_typeof(coalesce(new.proposed_properties->'bulk_risk_flags','[]'::jsonb))<>'array' then
      raise exception 'WNPH bulk reconstruction: bulk_risk_flags must be an array';
    end if;
    v_risk_flags:=coalesce(new.proposed_properties->'bulk_risk_flags','[]'::jsonb);

    if new.disposition='auto_admit' then
      if new.proposed_reading_state<>'usable' then
        raise exception 'WNPH bulk reconstruction: auto-admit under a bulk policy must promote only usable text';
      end if;
      if new.confidence<v_policy.min_proposal_confidence then
        raise exception 'WNPH bulk reconstruction: confidence % below policy floor %',new.confidence,v_policy.min_proposal_confidence;
      end if;
      if jsonb_array_length(v_risk_flags)<>0 then
        raise exception 'WNPH bulk reconstruction: auto-admit forbidden while risk flags remain';
      end if;
      if jsonb_typeof(new.proposed_properties->'bulk_consensus_observation_ids')<>'array' then
        raise exception 'WNPH bulk reconstruction: auto-admit requires bulk_consensus_observation_ids';
      end if;
      select array_agg(value::uuid order by ord) into v_consensus_ids
      from jsonb_array_elements_text(new.proposed_properties->'bulk_consensus_observation_ids') with ordinality x(value,ord);
      v_consensus_count:=coalesce(cardinality(v_consensus_ids),0);
      if v_consensus_count<v_policy.min_processor_families then
        raise exception 'WNPH bulk reconstruction: consensus evidence count % below policy minimum %',v_consensus_count,v_policy.min_processor_families;
      end if;
      if exists(select 1 from unnest(v_consensus_ids) x where not (x=any(new.source_observation_ids))) then
        raise exception 'WNPH bulk reconstruction: consensus evidence must be contained in source_observation_ids';
      end if;
      select
        count(distinct coalesce(o.processor->>'provider','')||':'||coalesce(o.processor->>'engine','')),
        count(distinct wnph.normalize_parallel_reading_text_v1(o.text_candidate)),
        count(*) filter (where wnph.normalize_parallel_reading_text_v1(o.text_candidate)<>'')
      into v_processor_families,v_normalized_readings,v_nonempty_normalized
      from wnph.publication_source_observations o
      join wnph.publication_source_assets a on a.id=o.source_asset_id
      where o.id=any(v_consensus_ids)
        and a.source_package_id=new.source_package_id
        and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
      if v_nonempty_normalized<>v_consensus_count then
        raise exception 'WNPH bulk reconstruction: every consensus observation must contain text';
      end if;
      if v_processor_families<v_policy.min_processor_families then
        raise exception 'WNPH bulk reconstruction: % processor families below policy minimum %',v_processor_families,v_policy.min_processor_families;
      end if;
      if v_policy.consensus_mode='normalized_exact' and v_normalized_readings<>1 then
        raise exception 'WNPH bulk reconstruction: normalized readings disagree; auto-admit refused';
      end if;
    end if;
  end if;

  if new.supersedes_proposal_id is not null then
    select * into v_old from wnph.publication_source_reconstruction_proposals where id=new.supersedes_proposal_id;
    if v_old.id is null
       or v_old.source_package_id<>new.source_package_id
       or v_old.proposal_key<>new.proposal_key
       or v_old.proposed_block_key<>new.proposed_block_key then
      raise exception 'WNPH reconstruction proposal: supersession must preserve source package, proposal_key and proposed_block_key';
    end if;
    if exists(select 1 from wnph.publication_source_reconstruction_proposals p where p.supersedes_proposal_id=v_old.id) then
      raise exception 'WNPH reconstruction proposal: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_source_reconstruction_proposals p
    where p.source_package_id=new.source_package_id and p.proposal_key=new.proposal_key
      and not exists(select 1 from wnph.publication_source_reconstruction_proposals child where child.supersedes_proposal_id=p.id)
  ) then
    raise exception 'WNPH reconstruction proposal: duplicate active proposal_key %',new.proposal_key;
  end if;
  return new;
end;
$$;

create or replace function public.wnph_claim_reconstruction_job_v1(p_runner_id text,p_lease_seconds integer default 240)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,wnph
as $$
declare
  v_job wnph.publication_source_reconstruction_jobs%rowtype;
  v_attempt wnph.publication_source_reconstruction_job_attempts%rowtype;
  v_pkg_key text; v_parent_key text; v_attempt_number integer; v_lease_token uuid; v_lease_expires timestamptz;
begin
  if coalesce(btrim(p_runner_id),'')='' then raise exception 'WNPH reconstruction claim requires runner id' using errcode='22023'; end if;
  if p_lease_seconds<60 or p_lease_seconds>900 then raise exception 'WNPH reconstruction lease must be between 60 and 900 seconds' using errcode='22023'; end if;
  update wnph.publication_source_reconstruction_job_attempts a set outcome='lease_expired',finished_at=coalesce(a.finished_at,now()),error_text=coalesce(a.error_text,'Worker lease expired before an explicit completion result.') where a.outcome='running' and a.lease_expires_at<=now();
  update wnph.publication_source_reconstruction_jobs j set status='failed',completed_at=coalesce(j.completed_at,now()),last_error=coalesce(j.last_error,'Reconstruction worker lease expired after maximum attempts.'),leased_by=null,lease_token=null,lease_expires_at=null,updated_at=now() where j.status='leased' and j.lease_expires_at<=now() and j.attempt_count>=j.max_attempts;
  select j.* into v_job from wnph.publication_source_reconstruction_jobs j where j.attempt_count<j.max_attempts and ((j.status='queued' and j.next_attempt_at<=now()) or (j.status='leased' and j.lease_expires_at<=now())) order by j.priority asc,j.created_at asc for update skip locked limit 1;
  if v_job.id is null then return null; end if;
  select p.canonical_key into v_pkg_key from wnph.publication_source_packages p where p.id=v_job.source_package_id and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id);
  select b.block_key into v_parent_key from wnph.publication_source_blocks b where b.id=v_job.target_parent_block_id and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
  if v_pkg_key is null or v_parent_key is null then update wnph.publication_source_reconstruction_jobs set status='failed',completed_at=now(),last_error='Source package or target parent block ceased to be active before execution.',updated_at=now() where id=v_job.id; return null; end if;
  v_attempt_number:=v_job.attempt_count+1; v_lease_token:=gen_random_uuid(); v_lease_expires:=now()+make_interval(secs=>p_lease_seconds);
  insert into wnph.publication_source_reconstruction_job_attempts(job_id,attempt_number,runner_id,lease_token,lease_expires_at) values(v_job.id,v_attempt_number,btrim(p_runner_id),v_lease_token,v_lease_expires) returning * into v_attempt;
  update wnph.publication_source_reconstruction_jobs set status='leased',attempt_count=v_attempt_number,leased_by=btrim(p_runner_id),lease_token=v_lease_token,lease_expires_at=v_lease_expires,updated_at=now() where id=v_job.id;
  return jsonb_build_object(
    'job_id',v_job.id,'attempt_id',v_attempt.id,'lease_token',v_lease_token,'source_package_key',v_pkg_key,
    'target_parent_block_key',v_parent_key,'asset_keys',to_jsonb(v_job.asset_keys),'proposed_reading_state',v_job.proposed_reading_state,
    'allow_usable_auto_admit',v_job.allow_usable_auto_admit,'proposed_block_key_prefix',v_job.proposed_block_key_prefix,
    'start_ordinal',v_job.start_ordinal,'requested_reconstruction_key',v_job.requested_reconstruction_key,
    'request_metadata',v_job.request_metadata
  );
end;
$$;

create or replace function wnph.seed_bulk_qa_samples_v1(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph
as $$
declare
  v_batch wnph.publication_source_bulk_batches%rowtype;
  v_policy wnph.publication_source_bulk_policies%rowtype;
  v_total integer; v_target integer; v_inserted integer;
begin
  select * into v_batch from wnph.publication_source_bulk_batches where id=p_batch_id for update;
  if v_batch.id is null then raise exception 'WNPH bulk QA: batch not found'; end if;
  select * into v_policy from wnph.publication_source_bulk_policies where id=v_batch.policy_id;
  select count(*) into v_total
  from wnph.publication_source_reconstruction_proposals p
  where p.source_package_id=v_batch.source_package_id
    and p.disposition='auto_admit'
    and p.proposed_properties->>'bulk_batch_key'=v_batch.batch_key
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id);
  if v_total=0 then raise exception 'WNPH bulk QA: no active auto-admitted proposals for batch %',v_batch.batch_key; end if;
  v_target:=least(v_policy.qa_max_samples,greatest(v_policy.qa_min_samples,ceil(v_total*v_policy.qa_sample_rate)::integer));
  insert into wnph.publication_source_bulk_qa_samples(batch_id,proposal_id,publication_source_block_id,sample_ordinal,sample_reason)
  select v_batch.id,p.id,b.id,row_number() over(order by md5(v_batch.id::text||':'||p.id::text))::integer,'deterministic_random_sample_of_auto_admitted_usable_text'
  from wnph.publication_source_reconstruction_proposals p
  left join wnph.publication_source_blocks b on b.source_package_id=p.source_package_id and b.block_key=p.proposed_block_key and b.source_provenance->>'reconstruction_proposal_id'=p.id::text
  where p.source_package_id=v_batch.source_package_id and p.disposition='auto_admit'
    and p.proposed_properties->>'bulk_batch_key'=v_batch.batch_key
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals c where c.supersedes_proposal_id=p.id)
  order by md5(v_batch.id::text||':'||p.id::text)
  limit v_target
  on conflict (batch_id,proposal_id) do nothing;
  get diagnostics v_inserted=row_count;
  update wnph.publication_source_bulk_batches set status='qa_pending',qa_status='pending',stats=stats||jsonb_build_object('qa_population',v_total,'qa_target_samples',v_target,'qa_inserted_samples',v_inserted) where id=v_batch.id;
  return jsonb_build_object('batch_key',v_batch.batch_key,'population',v_total,'target_samples',v_target,'inserted_samples',v_inserted);
end;
$$;