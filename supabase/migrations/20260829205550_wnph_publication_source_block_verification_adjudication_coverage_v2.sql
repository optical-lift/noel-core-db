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

  v_expected_hash:=encode(extensions.digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex');
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
    if exists(
      select 1
      from wnph.publication_source_reading_adjudications r
      where r.id in (
        select x::uuid from jsonb_array_elements_text(coalesce(v_block.properties->'governed_reading_adjudication_ids','[]'::jsonb)) x
      )
        and not exists(select 1 from wnph.publication_source_reading_adjudications child where child.supersedes_adjudication_id=r.id)
        and (not (r.start_asset_id=any(new.inspected_asset_ids)) or (r.end_asset_id is not null and not (r.end_asset_id=any(new.inspected_asset_ids))))
    ) then
      raise exception 'WNPH block verification: inspected pages do not cover every governed reading-adjudication source page behind this candidate';
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
      'text_content',v_block.text_content,'text_sha256',encode(extensions.digest(convert_to(v_block.text_content,'UTF8'),'sha256'),'hex'),
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
        select distinct o.source_asset_id from wnph.publication_source_observations o where o.id=any(v_proposal.source_observation_ids)
        union
        select r.start_asset_id
        from wnph.publication_source_reading_adjudications r
        where r.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_block.properties->'governed_reading_adjudication_ids','[]'::jsonb)) x)
          and not exists(select 1 from wnph.publication_source_reading_adjudications child where child.supersedes_adjudication_id=r.id)
        union
        select r.end_asset_id
        from wnph.publication_source_reading_adjudications r
        where r.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_block.properties->'governed_reading_adjudication_ids','[]'::jsonb)) x)
          and r.end_asset_id is not null
          and not exists(select 1 from wnph.publication_source_reading_adjudications child where child.supersedes_adjudication_id=r.id)
      )
    ),'[]'::jsonb),
    'active_reading_adjudications',coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at)
      from wnph.publication_source_reading_adjudications r
      where r.source_package_id=v_block.source_package_id
        and not exists(select 1 from wnph.publication_source_reading_adjudications child where child.supersedes_adjudication_id=r.id)
        and (
          r.start_observation_id=any(v_proposal.source_observation_ids)
          or r.end_observation_id=any(v_proposal.source_observation_ids)
          or r.id in (select x::uuid from jsonb_array_elements_text(coalesce(v_block.properties->'governed_reading_adjudication_ids','[]'::jsonb)) x)
        )
    ),'[]'::jsonb),
    'verification_history',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at) from wnph.publication_source_block_verifications v where v.block_id=v_block.id),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$function$;