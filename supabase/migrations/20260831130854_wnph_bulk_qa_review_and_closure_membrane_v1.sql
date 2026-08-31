update wnph.publication_source_bulk_policies
set risk_rules=risk_rules||jsonb_build_object('qa_requires_source_image_review',true)
where canonical_key='wnph:bulk-transmission:human-parallel:v1';

create or replace function wnph.validate_publication_source_bulk_qa_sample_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,wnph
as $$
declare
  v_policy wnph.publication_source_bulk_policies%rowtype;
  v_requires_image boolean:=false;
begin
  if tg_op<>'UPDATE' then return new; end if;

  if new.batch_id is distinct from old.batch_id
     or new.proposal_id is distinct from old.proposal_id
     or new.publication_source_block_id is distinct from old.publication_source_block_id
     or new.sample_ordinal is distinct from old.sample_ordinal
     or new.sample_reason is distinct from old.sample_reason
     or new.created_at is distinct from old.created_at then
    raise exception 'WNPH bulk QA: sample identity is immutable';
  end if;

  if old.outcome<>'pending' and row(new.*) is distinct from row(old.*) then
    raise exception 'WNPH bulk QA: finalized sample outcomes are immutable';
  end if;

  if jsonb_typeof(new.evidence)<>'object' then
    raise exception 'WNPH bulk QA: evidence must be an object';
  end if;

  if new.outcome='pending' then
    if new.reviewed_at is not null then
      raise exception 'WNPH bulk QA: pending sample may not have reviewed_at';
    end if;
    return new;
  end if;

  if new.outcome not in ('pass','minor_error','major_error') then
    raise exception 'WNPH bulk QA: invalid finalized outcome %',new.outcome;
  end if;
  if new.reviewed_at is null then
    raise exception 'WNPH bulk QA: finalized sample requires reviewed_at';
  end if;
  if coalesce(new.evidence->>'review_authority','')='' or coalesce(new.evidence->>'review_method','')='' then
    raise exception 'WNPH bulk QA: finalized sample requires review_authority and review_method evidence';
  end if;

  select p.* into v_policy
  from wnph.publication_source_bulk_batches b
  join wnph.publication_source_bulk_policies p on p.id=b.policy_id
  where b.id=new.batch_id;
  if v_policy.id is null then
    raise exception 'WNPH bulk QA: governing policy not found';
  end if;
  v_requires_image:=coalesce((v_policy.risk_rules->>'qa_requires_source_image_review')::boolean,false);
  if v_requires_image and not coalesce((new.evidence->>'source_image_checked')::boolean,false) then
    raise exception 'WNPH bulk QA: governing policy requires source_image_checked=true';
  end if;
  if v_requires_image and coalesce(new.evidence->>'source_image_uri','')='' then
    raise exception 'WNPH bulk QA: governing policy requires source_image_uri evidence';
  end if;

  return new;
end;
$$;

create trigger publication_source_bulk_qa_sample_update_guard_v1
before update on wnph.publication_source_bulk_qa_samples
for each row execute function wnph.validate_publication_source_bulk_qa_sample_v1();

create or replace function wnph.validate_publication_source_bulk_batch_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,wnph
as $$
declare
  v_policy wnph.publication_source_bulk_policies%rowtype;
  v_total integer:=0; v_pending integer:=0; v_major integer:=0; v_minor integer:=0;
  v_major_rate numeric:=0; v_missing_image_review integer:=0;
begin
  if tg_op<>'UPDATE' then return new; end if;

  if new.batch_key is distinct from old.batch_key
     or new.source_package_id is distinct from old.source_package_id
     or new.target_parent_block_id is distinct from old.target_parent_block_id
     or new.policy_id is distinct from old.policy_id
     or new.reconstruction_job_id is distinct from old.reconstruction_job_id
     or new.asset_keys is distinct from old.asset_keys
     or new.created_at is distinct from old.created_at then
    raise exception 'WNPH bulk QA: batch identity and evidence scope are immutable';
  end if;

  if new.qa_status='pass' or new.status='closed' then
    select * into v_policy from wnph.publication_source_bulk_policies where id=new.policy_id;
    select count(*),count(*) filter(where outcome='pending'),count(*) filter(where outcome='major_error'),count(*) filter(where outcome='minor_error')
      into v_total,v_pending,v_major,v_minor
    from wnph.publication_source_bulk_qa_samples where batch_id=new.id;
    if v_total=0 or v_pending<>0 then
      raise exception 'WNPH bulk QA: batch cannot pass/close with % samples and % pending',v_total,v_pending;
    end if;
    v_major_rate:=v_major::numeric/v_total::numeric;
    if v_major_rate>v_policy.max_major_error_rate then
      raise exception 'WNPH bulk QA: major error rate % exceeds policy maximum %',v_major_rate,v_policy.max_major_error_rate;
    end if;
    if coalesce((v_policy.risk_rules->>'qa_requires_source_image_review')::boolean,false) then
      select count(*) into v_missing_image_review
      from wnph.publication_source_bulk_qa_samples q
      where q.batch_id=new.id
        and (not coalesce((q.evidence->>'source_image_checked')::boolean,false)
             or coalesce(q.evidence->>'source_image_uri','')='');
      if v_missing_image_review<>0 then
        raise exception 'WNPH bulk QA: % finalized samples lack required source-image review evidence',v_missing_image_review;
      end if;
    end if;
  end if;

  if new.status='closed' and new.qa_status<>'pass' then
    raise exception 'WNPH bulk QA: closed batch requires qa_status=pass';
  end if;
  if new.qa_status='pass' and new.status<>'closed' then
    raise exception 'WNPH bulk QA: qa_status=pass is only valid on a closed batch';
  end if;
  if new.completed_at is not null and new.status not in ('closed','failed','cancelled') then
    raise exception 'WNPH bulk QA: completed_at requires a terminal batch status';
  end if;

  return new;
end;
$$;

create trigger publication_source_bulk_batch_update_guard_v1
before update on wnph.publication_source_bulk_batches
for each row execute function wnph.validate_publication_source_bulk_batch_v1();

create or replace function wnph.record_bulk_qa_review_v1(
  p_sample_id uuid,
  p_outcome text,
  p_evidence jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph
as $$
declare
  v_sample wnph.publication_source_bulk_qa_samples%rowtype;
begin
  if p_outcome not in ('pass','minor_error','major_error') then
    raise exception 'WNPH bulk QA: outcome must be pass, minor_error, or major_error';
  end if;
  if jsonb_typeof(coalesce(p_evidence,'null'::jsonb))<>'object' then
    raise exception 'WNPH bulk QA: review evidence must be an object';
  end if;
  select * into v_sample from wnph.publication_source_bulk_qa_samples where id=p_sample_id for update;
  if v_sample.id is null then raise exception 'WNPH bulk QA: sample not found'; end if;
  if v_sample.outcome<>'pending' then raise exception 'WNPH bulk QA: sample already finalized as %',v_sample.outcome; end if;

  update wnph.publication_source_bulk_qa_samples
  set outcome=p_outcome,evidence=p_evidence,reviewed_at=now()
  where id=p_sample_id
  returning * into v_sample;

  return jsonb_build_object('sample_id',v_sample.id,'batch_id',v_sample.batch_id,'sample_ordinal',v_sample.sample_ordinal,'outcome',v_sample.outcome,'reviewed_at',v_sample.reviewed_at);
end;
$$;

create or replace function wnph.finalize_bulk_qa_v1(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph
as $$
declare
  v_batch wnph.publication_source_bulk_batches%rowtype;
  v_policy wnph.publication_source_bulk_policies%rowtype;
  v_total integer:=0; v_pending integer:=0; v_major integer:=0; v_minor integer:=0; v_pass integer:=0;
  v_major_rate numeric:=0;
begin
  select * into v_batch from wnph.publication_source_bulk_batches where id=p_batch_id for update;
  if v_batch.id is null then raise exception 'WNPH bulk QA: batch not found'; end if;
  if v_batch.status<>'qa_pending' or v_batch.qa_status<>'pending' then
    raise exception 'WNPH bulk QA: batch is not pending QA';
  end if;
  select * into v_policy from wnph.publication_source_bulk_policies where id=v_batch.policy_id;
  select count(*),count(*) filter(where outcome='pending'),count(*) filter(where outcome='major_error'),count(*) filter(where outcome='minor_error'),count(*) filter(where outcome='pass')
    into v_total,v_pending,v_major,v_minor,v_pass
  from wnph.publication_source_bulk_qa_samples where batch_id=p_batch_id;
  if v_total=0 or v_pending<>0 then
    raise exception 'WNPH bulk QA: cannot finalize with % samples and % pending',v_total,v_pending;
  end if;
  v_major_rate:=v_major::numeric/v_total::numeric;

  if v_major_rate>v_policy.max_major_error_rate then
    update wnph.publication_source_bulk_batches
    set qa_status='fail',status='failed',completed_at=now(),
        stats=stats||jsonb_build_object('qa_samples_reviewed',v_total,'qa_pass_samples',v_pass,'qa_minor_errors',v_minor,'qa_major_errors',v_major,'qa_major_error_rate',v_major_rate)
    where id=p_batch_id
    returning * into v_batch;
  else
    update wnph.publication_source_bulk_batches
    set qa_status='pass',status='closed',completed_at=now(),
        stats=stats||jsonb_build_object('qa_samples_reviewed',v_total,'qa_pass_samples',v_pass,'qa_minor_errors',v_minor,'qa_major_errors',v_major,'qa_major_error_rate',v_major_rate)
    where id=p_batch_id
    returning * into v_batch;
  end if;

  return jsonb_build_object('batch_id',v_batch.id,'batch_key',v_batch.batch_key,'status',v_batch.status,'qa_status',v_batch.qa_status,'sample_count',v_total,'pass',v_pass,'minor_errors',v_minor,'major_errors',v_major,'major_error_rate',v_major_rate,'completed_at',v_batch.completed_at);
end;
$$;

revoke execute on function wnph.record_bulk_qa_review_v1(uuid,text,jsonb) from public,anon,authenticated;
revoke execute on function wnph.finalize_bulk_qa_v1(uuid) from public,anon,authenticated;