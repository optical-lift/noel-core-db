create table wnph.publication_source_block_verifications (
  id uuid primary key default gen_random_uuid(),
  verification_key text not null unique check (btrim(verification_key) <> ''),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  block_id uuid not null references wnph.publication_source_blocks(id),
  reconstruction_proposal_id uuid not null references wnph.publication_source_reconstruction_proposals(id),
  verification_result text not null check (verification_result in ('verified_unchanged','needs_adjudication','rejected','unresolved')),
  verification_authority text not null check (btrim(verification_authority) <> ''),
  derivation_method text not null check (btrim(derivation_method) <> ''),
  candidate_text_sha256 text not null check (candidate_text_sha256 ~ '^[0-9a-f]{64}$'),
  inspected_asset_ids uuid[] not null default '{}'::uuid[],
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  evidence jsonb not null default '{}'::jsonb,
  supersedes_verification_id uuid references wnph.publication_source_block_verifications(id),
  created_at timestamptz not null default now(),
  check (supersedes_verification_id is null or supersedes_verification_id <> id)
);

create index publication_source_block_verifications_package_idx
  on wnph.publication_source_block_verifications(source_package_id);
create index publication_source_block_verifications_block_idx
  on wnph.publication_source_block_verifications(block_id,created_at desc);
create index publication_source_block_verifications_proposal_idx
  on wnph.publication_source_block_verifications(reconstruction_proposal_id);
create index publication_source_block_verifications_supersedes_idx
  on wnph.publication_source_block_verifications(supersedes_verification_id)
  where supersedes_verification_id is not null;

comment on table wnph.publication_source_block_verifications is
  'Append-only block-level source-image verification ledger. Verification may certify an existing candidate unchanged or route it back to adjudication; it never edits reading text.';

create or replace function wnph.validate_publication_source_block_verification_v1()
returns trigger
language plpgsql
set search_path to pg_catalog,wnph,public
as $function$
declare
  v_package wnph.publication_source_packages%rowtype;
  v_block wnph.publication_source_blocks%rowtype;
  v_proposal wnph.publication_source_reconstruction_proposals%rowtype;
  v_old wnph.publication_source_block_verifications%rowtype;
  v_asset_id uuid;
  v_expected_hash text;
  v_distinct_assets integer;
begin
  if jsonb_typeof(new.evidence) <> 'object' then
    raise exception 'WNPH block verification: evidence must be an object';
  end if;

  if exists(select 1 from unnest(new.inspected_asset_ids) x where x is null) then
    raise exception 'WNPH block verification: inspected asset ids cannot contain null';
  end if;
  select count(distinct x) into v_distinct_assets from unnest(new.inspected_asset_ids) x;
  if v_distinct_assets <> cardinality(new.inspected_asset_ids) then
    raise exception 'WNPH block verification: inspected asset ids cannot contain duplicates';
  end if;

  select * into v_package
  from wnph.publication_source_packages p
  where p.id=new.source_package_id
    and not exists(select 1 from wnph.publication_source_packages child where child.supersedes_package_id=p.id);
  if v_package.id is null then
    raise exception 'WNPH block verification: source package must be active';
  end if;

  select * into v_block
  from wnph.publication_source_blocks b
  where b.id=new.block_id
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);
  if v_block.id is null or v_block.source_package_id<>new.source_package_id then
    raise exception 'WNPH block verification: block must be active and inside the source package';
  end if;
  if v_block.text_content is null then
    raise exception 'WNPH block verification: text-bearing block required';
  end if;

  select * into v_proposal
  from wnph.publication_source_reconstruction_proposals p
  where p.id=new.reconstruction_proposal_id
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals child where child.supersedes_proposal_id=p.id);
  if v_proposal.id is null
     or v_proposal.source_package_id<>new.source_package_id
     or v_proposal.proposed_block_key<>v_block.block_key
     or v_proposal.proposed_text_content is distinct from v_block.text_content then
    raise exception 'WNPH block verification: active reconstruction proposal must identify the unchanged candidate block text';
  end if;

  v_expected_hash:=encode(digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex');
  if new.candidate_text_sha256<>v_expected_hash then
    raise exception 'WNPH block verification: candidate text hash does not match current block text';
  end if;

  foreach v_asset_id in array new.inspected_asset_ids loop
    if not exists(
      select 1 from wnph.publication_source_assets a
      where a.id=v_asset_id
        and a.source_package_id=new.source_package_id
        and a.source_surrogate_id is not null
        and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id)
    ) then
      raise exception 'WNPH block verification: inspected asset % must be an active source-surrogate asset in the same package',v_asset_id;
    end if;
  end loop;

  if new.verification_result in ('verified_unchanged','needs_adjudication','rejected') then
    if v_block.reading_state<>'candidate' then
      raise exception 'WNPH block verification: resolved source-image review requires a candidate block';
    end if;
    if cardinality(new.inspected_asset_ids)=0 then
      raise exception 'WNPH block verification: resolved source-image review requires inspected source assets';
    end if;
    if coalesce((new.evidence->>'page_image_inspected')::boolean,false)<>true then
      raise exception 'WNPH block verification: resolved source-image review requires literal page-image inspection evidence';
    end if;
  end if;

  if new.verification_result='verified_unchanged' then
    if coalesce((new.evidence->>'candidate_text_compared_to_source_image')::boolean,false)<>true then
      raise exception 'WNPH block verification: unchanged verification requires an explicit text-to-image comparison assertion';
    end if;
    if exists(
      select 1
      from unnest(v_proposal.source_observation_ids) observation_id
      left join wnph.publication_source_observations o on o.id=observation_id
      where o.id is null
         or not (o.source_asset_id=any(new.inspected_asset_ids))
         or exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id)
    ) then
      raise exception 'WNPH block verification: inspected pages do not cover every active source observation behind this candidate';
    end if;
  end if;

  if new.supersedes_verification_id is not null then
    select * into v_old from wnph.publication_source_block_verifications where id=new.supersedes_verification_id;
    if v_old.id is null
       or v_old.source_package_id<>new.source_package_id
       or v_old.block_id<>new.block_id
       or v_old.reconstruction_proposal_id<>new.reconstruction_proposal_id then
      raise exception 'WNPH block verification: supersession must preserve package, block and reconstruction proposal';
    end if;
    if exists(select 1 from wnph.publication_source_block_verifications child where child.supersedes_verification_id=v_old.id) then
      raise exception 'WNPH block verification: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1 from wnph.publication_source_block_verifications v
    where v.block_id=new.block_id
      and not exists(select 1 from wnph.publication_source_block_verifications child where child.supersedes_verification_id=v.id)
  ) then
    raise exception 'WNPH block verification: block already has an active verification record; supersede it explicitly';
  end if;

  return new;
end;
$function$;

create trigger validate_publication_source_block_verification_v1
before insert on wnph.publication_source_block_verifications
for each row execute function wnph.validate_publication_source_block_verification_v1();

create or replace function wnph.reject_publication_source_block_verification_mutation_v1()
returns trigger
language plpgsql
set search_path to pg_catalog,wnph
as $function$
begin
  raise exception 'WNPH block verification ledger is append-only; supersede by inserting a new verification record';
end;
$function$;

create trigger publication_source_block_verifications_append_only_v1
before update or delete on wnph.publication_source_block_verifications
for each row execute function wnph.reject_publication_source_block_verification_mutation_v1();

create or replace function public.wnph_source_block_verification_packet_v1(p_block_key text)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,wnph,public
as $function$
declare
  v_block wnph.publication_source_blocks%rowtype;
  v_proposal wnph.publication_source_reconstruction_proposals%rowtype;
  v_parent wnph.publication_source_blocks%rowtype;
  v_result jsonb;
begin
  select * into v_block
  from wnph.publication_source_blocks b
  where b.block_key=p_block_key
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;
  if v_block.id is null then raise exception 'WNPH verification packet: active block not found' using errcode='P0002'; end if;

  select * into v_proposal
  from wnph.publication_source_reconstruction_proposals p
  where p.source_package_id=v_block.source_package_id
    and p.proposed_block_key=v_block.block_key
    and p.proposed_text_content is not distinct from v_block.text_content
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals child where child.supersedes_proposal_id=p.id)
  order by p.created_at desc limit 1;
  if v_proposal.id is null then raise exception 'WNPH verification packet: active reconstruction proposal not found' using errcode='P0002'; end if;

  select * into v_parent from wnph.publication_source_blocks where id=v_block.parent_block_id;

  select jsonb_build_object(
    'contract_version','wnph_source_block_verification_packet_v1',
    'truth_boundary',jsonb_build_object(
      'page_image_must_be_literally_inspected',true,
      'ocr_is_not_verification_authority',true,
      'verification_cannot_edit_text',true,
      'mismatch_routes_back_to_adjudication_and_reconstruction',true
    ),
    'block',jsonb_build_object(
      'id',v_block.id,'block_key',v_block.block_key,'parent_block_key',v_parent.block_key,'ordinal',v_block.ordinal,
      'block_type',v_block.block_type,'semantic_role',v_block.semantic_role,'reading_state',v_block.reading_state,
      'text_content',v_block.text_content,'text_sha256',encode(digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex'),
      'source_provenance',v_block.source_provenance,'properties',v_block.properties
    ),
    'reconstruction_proposal',jsonb_build_object(
      'id',v_proposal.id,'proposal_key',v_proposal.proposal_key,'disposition',v_proposal.disposition,
      'confidence',v_proposal.confidence,'source_observation_ids',v_proposal.source_observation_ids,
      'algorithm',v_proposal.algorithm,'proposed_source_provenance',v_proposal.proposed_source_provenance
    ),
    'source_assets',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',a.id,'asset_key',a.asset_key,'asset_role',a.asset_role,'media_type',a.media_type,
        'source_surrogate_id',a.source_surrogate_id,'evidence_source_id',a.evidence_source_id,
        'source_locator',a.source_locator,'metadata',a.metadata,
        'proposal_observations',(
          select coalesce(jsonb_agg(jsonb_build_object(
            'id',o.id,'observation_key',o.observation_key,'observation_kind',o.observation_kind,'ordinal',o.ordinal,
            'text_candidate',o.text_candidate,'confidence',o.confidence,'derivation_method',o.derivation_method,
            'processor',o.processor,'external_locator',o.external_locator
          ) order by o.ordinal,o.id),'[]'::jsonb)
          from wnph.publication_source_observations o
          where o.source_asset_id=a.id and o.id=any(v_proposal.source_observation_ids)
        )
      ) order by coalesce((a.source_locator->>'printed_page')::int,2147483647),a.asset_key)
      from wnph.publication_source_assets a
      where a.id in (
        select distinct o.source_asset_id
        from wnph.publication_source_observations o
        where o.id=any(v_proposal.source_observation_ids)
      )
    ),'[]'::jsonb),
    'active_reading_adjudications',coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at)
      from wnph.publication_source_reading_adjudications r
      where r.source_package_id=v_block.source_package_id
        and not exists(select 1 from wnph.publication_source_reading_adjudications child where child.supersedes_adjudication_id=r.id)
        and (r.start_observation_id=any(v_proposal.source_observation_ids) or r.end_observation_id=any(v_proposal.source_observation_ids))
    ),'[]'::jsonb),
    'verification_history',coalesce((
      select jsonb_agg(to_jsonb(v) order by v.created_at)
      from wnph.publication_source_block_verifications v where v.block_id=v_block.id
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

create or replace function public.wnph_record_source_block_verification_v1(
  p_verification_key text,
  p_block_key text,
  p_verification_result text,
  p_verification_authority text,
  p_derivation_method text,
  p_inspected_asset_keys text[],
  p_confidence numeric,
  p_evidence jsonb,
  p_supersedes_verification_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,wnph,public
as $function$
declare
  v_block wnph.publication_source_blocks%rowtype;
  v_proposal wnph.publication_source_reconstruction_proposals%rowtype;
  v_asset_ids uuid[];
  v_supersedes uuid;
  v_id uuid;
begin
  if p_verification_key is null or btrim(p_verification_key)='' then raise exception 'Verification key is required' using errcode='22023'; end if;
  if p_block_key is null or btrim(p_block_key)='' then raise exception 'Block key is required' using errcode='22023'; end if;

  select * into v_block from wnph.publication_source_blocks b
  where b.block_key=p_block_key
    and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;
  if v_block.id is null then raise exception 'Active source block not found' using errcode='P0002'; end if;

  select * into v_proposal from wnph.publication_source_reconstruction_proposals p
  where p.source_package_id=v_block.source_package_id and p.proposed_block_key=v_block.block_key
    and p.proposed_text_content is not distinct from v_block.text_content
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals child where child.supersedes_proposal_id=p.id)
  order by p.created_at desc limit 1;
  if v_proposal.id is null then raise exception 'Active reconstruction proposal not found' using errcode='P0002'; end if;

  if coalesce(cardinality(p_inspected_asset_keys),0)=0 then
    v_asset_ids:='{}'::uuid[];
  else
    select array_agg(a.id order by a.asset_key) into v_asset_ids
    from wnph.publication_source_assets a
    where a.source_package_id=v_block.source_package_id
      and a.asset_key=any(p_inspected_asset_keys)
      and not exists(select 1 from wnph.publication_source_assets child where child.supersedes_asset_id=a.id);
    if cardinality(v_asset_ids)<>cardinality(p_inspected_asset_keys) then
      raise exception 'One or more inspected asset keys were not active assets in the source package' using errcode='22023';
    end if;
  end if;

  if p_supersedes_verification_key is not null then
    select id into v_supersedes from wnph.publication_source_block_verifications where verification_key=p_supersedes_verification_key;
    if v_supersedes is null then raise exception 'Superseded verification key was not found' using errcode='P0002'; end if;
  end if;

  insert into wnph.publication_source_block_verifications(
    verification_key,source_package_id,block_id,reconstruction_proposal_id,verification_result,
    verification_authority,derivation_method,candidate_text_sha256,inspected_asset_ids,confidence,evidence,supersedes_verification_id
  ) values(
    p_verification_key,v_block.source_package_id,v_block.id,v_proposal.id,p_verification_result,
    p_verification_authority,p_derivation_method,encode(digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex'),
    coalesce(v_asset_ids,'{}'::uuid[]),p_confidence,coalesce(p_evidence,'{}'::jsonb),v_supersedes
  ) returning id into v_id;

  return jsonb_build_object('verification_id',v_id,'verification_key',p_verification_key,'block_key',v_block.block_key,
    'verification_result',p_verification_result,'reading_state',v_block.reading_state,'text_changed',false);
end;
$function$;

create or replace function public.wnph_admit_verified_source_block_v1(p_verification_key text)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog,wnph,public
as $function$
declare
  v_verification wnph.publication_source_block_verifications%rowtype;
  v_block wnph.publication_source_blocks%rowtype;
  v_package wnph.publication_source_packages%rowtype;
  v_parent wnph.publication_source_blocks%rowtype;
  v_work_id uuid;
  v_surrogate_id uuid;
  v_surrogate_count integer;
  v_act_id uuid;
  v_act_key text;
  v_asset_id uuid;
  v_source_id uuid;
  v_confidence text;
  v_current_hash text;
begin
  select * into v_verification
  from wnph.publication_source_block_verifications v
  where v.verification_key=p_verification_key
    and not exists(select 1 from wnph.publication_source_block_verifications child where child.supersedes_verification_id=v.id);
  if v_verification.id is null then raise exception 'Active verification record not found' using errcode='P0002'; end if;
  if v_verification.verification_result<>'verified_unchanged' then
    raise exception 'Only verified_unchanged source-image reviews may cross canonical text admission' using errcode='55000';
  end if;

  select * into v_block from wnph.publication_source_blocks where id=v_verification.block_id for update;
  if v_block.id is null then raise exception 'Verification block not found' using errcode='P0002'; end if;
  v_current_hash:=encode(digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex');
  if v_current_hash<>v_verification.candidate_text_sha256 then
    raise exception 'Candidate text changed after source-image verification; re-verify before admission' using errcode='55000';
  end if;
  if v_block.reading_state='verified' and v_block.source_provenance->>'block_verification_key'=p_verification_key then
    return jsonb_build_object('admitted',true,'deduplicated',true,'block_key',v_block.block_key,'reading_state',v_block.reading_state);
  end if;
  if v_block.reading_state<>'candidate' then
    raise exception 'Verified admission requires the same candidate block that was inspected' using errcode='55000';
  end if;

  select * into v_package from wnph.publication_source_packages where id=v_verification.source_package_id;
  select work_id into v_work_id from wnph.expressions where id=v_package.expression_id;
  select * into v_parent from wnph.publication_source_blocks where id=v_block.parent_block_id;

  select count(distinct a.source_surrogate_id),min(a.source_surrogate_id)
  into v_surrogate_count,v_surrogate_id
  from wnph.publication_source_assets a
  where a.id=any(v_verification.inspected_asset_ids) and a.source_surrogate_id is not null;
  if v_surrogate_count<>1 or v_surrogate_id is null then
    raise exception 'Verified admission requires one governed historical surrogate shared by all inspected assets' using errcode='55000';
  end if;

  v_act_key:='wnph:canonical-text-admission:block-verification:'||v_verification.id::text;
  select id into v_act_id from wnph.transmission_acts where canonical_key=v_act_key;
  if v_act_id is null then
    v_confidence:=case when v_verification.confidence is null then null when v_verification.confidence>=0.99 then 'certain' when v_verification.confidence>=0.90 then 'high' else 'moderate' end;
    insert into wnph.transmission_acts(
      canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
    ) values(
      v_act_key,v_package.recovery_case_id,v_work_id,'verified_transcription',
      'Admit one source-image-verified publication source block without altering its candidate text.',
      'Block-level verification certifies the existing candidate unchanged against explicitly inspected source images. Any textual mismatch must return to observation-level adjudication and reconstruction rather than being edited during admission.',
      'system_recorded',v_confidence,
      jsonb_build_object(
        'canonical_text_admission',true,'source_image_verified',true,'page_image_is_authority',true,
        'block_level_verification',true,'verification_id',v_verification.id,'verification_key',v_verification.verification_key,
        'candidate_text_sha256',v_verification.candidate_text_sha256,'inspected_asset_ids',to_jsonb(v_verification.inspected_asset_ids),
        'verification_authority',v_verification.verification_authority,'derivation_method',v_verification.derivation_method,
        'verification_evidence',v_verification.evidence
      )
    ) returning id into v_act_id;

    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator,notes)
    values(v_act_id,'input','preferred_historical_source',v_surrogate_id,'{}'::jsonb,'Historical source surrogate carrying the inspected page image(s).');

    foreach v_asset_id in array v_verification.inspected_asset_ids loop
      insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_asset_id,locator,notes)
      select v_act_id,'input','inspected_source_page',a.id,a.source_locator,'This exact source page was declared visually inspected by the governed block verification.'
      from wnph.publication_source_assets a where a.id=v_asset_id;
    end loop;

    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id,locator,notes)
    values(v_act_id,'context','canonical_publication_source',v_package.id,'{}'::jsonb,null);
    if v_parent.id is not null then
      insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator,notes)
      values(v_act_id,'context','paragraph_stream',v_parent.id,'{}'::jsonb,null);
    end if;
    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_block_id,locator,notes)
    values(v_act_id,'output','canonical_paragraph',v_block.id,jsonb_build_object('block_key',v_block.block_key,'ordinal',v_block.ordinal),
      'Output is the same text-bearing block that was source-image verified; text is not modified by admission.');

    for v_source_id in
      select distinct a.evidence_source_id from wnph.publication_source_assets a
      where a.id=any(v_verification.inspected_asset_ids) and a.evidence_source_id is not null
    loop
      insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
      values(v_act_id,v_source_id,'supports',coalesce(v_confidence,'high'),
        'Repository source record anchors the exact source asset(s) declared visually inspected for this block-level verification.');
    end loop;
  end if;

  update wnph.publication_source_blocks
  set reading_state='verified',
      source_provenance=coalesce(source_provenance,'{}'::jsonb)||jsonb_build_object(
        'verification_status','source_image_verified',
        'block_verification_id',v_verification.id,
        'block_verification_key',v_verification.verification_key,
        'verified_text_sha256',v_verification.candidate_text_sha256,
        'canonical_text_admission_act_id',v_act_id,
        'text_unchanged_during_verification',true
      )
  where id=v_block.id;

  return jsonb_build_object('admitted',true,'deduplicated',false,'verification_id',v_verification.id,
    'transmission_act_id',v_act_id,'block_key',v_block.block_key,'reading_state','verified','text_changed',false);
end;
$function$;

revoke all on table wnph.publication_source_block_verifications from public,anon,authenticated;
revoke all on function public.wnph_source_block_verification_packet_v1(text) from public,anon,authenticated;
revoke all on function public.wnph_record_source_block_verification_v1(text,text,text,text,text,text[],numeric,jsonb,text) from public,anon,authenticated;
revoke all on function public.wnph_admit_verified_source_block_v1(text) from public,anon,authenticated;
grant execute on function public.wnph_source_block_verification_packet_v1(text) to service_role;
grant execute on function public.wnph_record_source_block_verification_v1(text,text,text,text,text,text[],numeric,jsonb,text) to service_role;
grant execute on function public.wnph_admit_verified_source_block_v1(text) to service_role;