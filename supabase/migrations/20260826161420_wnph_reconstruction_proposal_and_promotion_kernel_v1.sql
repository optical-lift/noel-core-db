create table wnph.publication_source_reconstruction_proposals (
  id uuid primary key default gen_random_uuid(),
  source_package_id uuid not null references wnph.publication_source_packages(id),
  proposal_key text not null check (btrim(proposal_key)<>''),
  target_parent_block_id uuid not null references wnph.publication_source_blocks(id),
  proposed_block_key text not null check (btrim(proposed_block_key)<>''),
  proposed_ordinal integer not null check (proposed_ordinal>=0),
  proposed_block_type text not null check (btrim(proposed_block_type)<>''),
  proposed_semantic_role text,
  proposed_text_content text not null check (btrim(proposed_text_content)<>''),
  proposed_reading_state text not null check (proposed_reading_state in ('candidate','usable')),
  source_observation_ids uuid[] not null check (cardinality(source_observation_ids)>=1),
  confidence numeric not null check (confidence>=0 and confidence<=1),
  disposition text not null check (disposition in ('auto_admit','review','reject')),
  review_reasons jsonb not null default '[]'::jsonb,
  proposed_properties jsonb not null default '{}'::jsonb,
  proposed_source_provenance jsonb not null default '{}'::jsonb,
  algorithm jsonb not null default '{}'::jsonb,
  supersedes_proposal_id uuid references wnph.publication_source_reconstruction_proposals(id),
  created_at timestamptz not null default now(),
  constraint publication_source_reconstruction_proposals_supersedes_not_self check (
    supersedes_proposal_id is null or supersedes_proposal_id<>id
  )
);

comment on table wnph.publication_source_reconstruction_proposals is
  'Append-only reconstruction proposals between source observations and semantic publication blocks. Machine or human reconstruction may propose candidate/usable text only; verified/adjudicated custody remains exclusively governed by the canonical admission membrane.';

create index publication_source_reconstruction_proposals_package_parent_idx
  on wnph.publication_source_reconstruction_proposals(source_package_id,target_parent_block_id,proposed_ordinal);
create index publication_source_reconstruction_proposals_disposition_idx
  on wnph.publication_source_reconstruction_proposals(source_package_id,disposition);
create index publication_source_reconstruction_proposals_supersedes_idx
  on wnph.publication_source_reconstruction_proposals(supersedes_proposal_id)
  where supersedes_proposal_id is not null;
create index publication_source_reconstruction_proposals_observation_ids_gin
  on wnph.publication_source_reconstruction_proposals using gin(source_observation_ids);

create or replace function wnph.validate_publication_source_reconstruction_proposal_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_parent_package uuid;
  v_obs_id uuid;
  v_obs_package uuid;
  v_old wnph.publication_source_reconstruction_proposals%rowtype;
  v_distinct_obs integer;
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
    and not exists(
      select 1 from wnph.publication_source_blocks child
      where child.supersedes_block_id=b.id
    );

  if v_parent_package is null or v_parent_package<>new.source_package_id then
    raise exception 'WNPH reconstruction proposal: target parent must be an active block in the same source package';
  end if;

  select count(distinct x) into v_distinct_obs
  from unnest(new.source_observation_ids) x;
  if v_distinct_obs<>cardinality(new.source_observation_ids) then
    raise exception 'WNPH reconstruction proposal: source_observation_ids may not contain duplicates';
  end if;

  foreach v_obs_id in array new.source_observation_ids loop
    select a.source_package_id into v_obs_package
    from wnph.publication_source_observations o
    join wnph.publication_source_assets a on a.id=o.source_asset_id
    where o.id=v_obs_id
      and not exists(
        select 1 from wnph.publication_source_observations child
        where child.supersedes_observation_id=o.id
      );

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

  if new.supersedes_proposal_id is not null then
    select * into v_old
    from wnph.publication_source_reconstruction_proposals
    where id=new.supersedes_proposal_id;

    if v_old.id is null
       or v_old.source_package_id<>new.source_package_id
       or v_old.proposal_key<>new.proposal_key
       or v_old.proposed_block_key<>new.proposed_block_key then
      raise exception 'WNPH reconstruction proposal: supersession must preserve source package, proposal_key and proposed_block_key';
    end if;
    if exists(
      select 1 from wnph.publication_source_reconstruction_proposals p
      where p.supersedes_proposal_id=v_old.id
    ) then
      raise exception 'WNPH reconstruction proposal: supersession fork is not allowed';
    end if;
  elsif exists(
    select 1
    from wnph.publication_source_reconstruction_proposals p
    where p.source_package_id=new.source_package_id
      and p.proposal_key=new.proposal_key
      and not exists(
        select 1 from wnph.publication_source_reconstruction_proposals child
        where child.supersedes_proposal_id=p.id
      )
  ) then
    raise exception 'WNPH reconstruction proposal: duplicate active proposal_key %',new.proposal_key;
  end if;

  return new;
end;
$function$;

revoke all on function wnph.validate_publication_source_reconstruction_proposal_v1() from public,anon,authenticated,service_role;

create trigger publication_source_reconstruction_proposals_insert_validation_v1
before insert on wnph.publication_source_reconstruction_proposals
for each row execute function wnph.validate_publication_source_reconstruction_proposal_v1();

create trigger publication_source_reconstruction_proposals_append_only
before update or delete on wnph.publication_source_reconstruction_proposals
for each row execute function wnph.reject_append_only_mutation();

create or replace function wnph.promote_publication_source_reconstruction_proposal_v1(p_proposal_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','wnph'
as $function$
declare
  v_p wnph.publication_source_reconstruction_proposals%rowtype;
  v_block_id uuid;
  v_existing wnph.publication_source_blocks%rowtype;
begin
  select p.* into v_p
  from wnph.publication_source_reconstruction_proposals p
  where p.id=p_proposal_id
    and not exists(
      select 1 from wnph.publication_source_reconstruction_proposals child
      where child.supersedes_proposal_id=p.id
    );

  if v_p.id is null then
    raise exception 'WNPH reconstruction promotion: active proposal not found';
  end if;
  if v_p.disposition<>'auto_admit' then
    raise exception 'WNPH reconstruction promotion: only auto_admit proposals may be promoted';
  end if;
  if v_p.proposed_reading_state not in ('candidate','usable') then
    raise exception 'WNPH reconstruction promotion: reconstruction may promote only candidate/usable reading states';
  end if;

  select b.* into v_existing
  from wnph.publication_source_blocks b
  where b.source_package_id=v_p.source_package_id
    and b.block_key=v_p.proposed_block_key
    and not exists(
      select 1 from wnph.publication_source_blocks child
      where child.supersedes_block_id=b.id
    )
  order by b.created_at desc
  limit 1;

  if v_existing.id is not null then
    if v_existing.source_provenance->>'reconstruction_proposal_id'=v_p.id::text then
      return v_existing.id;
    end if;
    raise exception 'WNPH reconstruction promotion: active block_key % already exists independently of this proposal',v_p.proposed_block_key;
  end if;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
    text_content,properties,source_provenance,reading_state
  ) values (
    v_p.source_package_id,
    v_p.proposed_block_key,
    v_p.target_parent_block_id,
    v_p.proposed_ordinal,
    v_p.proposed_block_type,
    v_p.proposed_semantic_role,
    v_p.proposed_text_content,
    v_p.proposed_properties || jsonb_build_object(
      'reconstruction_confidence',v_p.confidence,
      'reconstruction_disposition',v_p.disposition
    ),
    v_p.proposed_source_provenance || jsonb_build_object(
      'reconstruction_proposal_id',v_p.id,
      'source_observation_ids',to_jsonb(v_p.source_observation_ids),
      'reconstruction_algorithm',v_p.algorithm
    ),
    v_p.proposed_reading_state
  ) returning id into v_block_id;

  return v_block_id;
end;
$function$;

revoke all on function wnph.promote_publication_source_reconstruction_proposal_v1(uuid) from public,anon,authenticated,service_role;

create or replace function public.wnph_commit_reconstruction_batch_v1(
  p_source_package_key text,
  p_reconstruction_key text,
  p_proposals jsonb,
  p_run_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_pkg_id uuid;
  v_item jsonb;
  v_proposal_id uuid;
  v_existing wnph.publication_source_reconstruction_proposals%rowtype;
  v_obs_ids uuid[];
  v_inserted integer:=0;
  v_skipped integer:=0;
  v_promoted integer:=0;
  v_review integer:=0;
  v_reject integer:=0;
  v_block_id uuid;
  v_count integer;
begin
  if coalesce(btrim(p_source_package_key),'')='' or coalesce(btrim(p_reconstruction_key),'')='' then
    raise exception 'WNPH reconstruction batch: source package key and reconstruction key are required';
  end if;
  if jsonb_typeof(p_proposals)<>'array' then
    raise exception 'WNPH reconstruction batch: proposals must be an array';
  end if;
  v_count:=jsonb_array_length(p_proposals);
  if v_count<1 or v_count>10000 then
    raise exception 'WNPH reconstruction batch: proposal count % outside supported range 1..10000',v_count;
  end if;
  if jsonb_typeof(coalesce(p_run_metadata,'{}'::jsonb))<>'object' then
    raise exception 'WNPH reconstruction batch: run metadata must be an object';
  end if;

  select p.id into v_pkg_id
  from wnph.publication_source_packages p
  where p.canonical_key=p_source_package_key
    and not exists(
      select 1 from wnph.publication_source_packages child
      where child.supersedes_package_id=p.id
    )
  order by p.created_at desc
  limit 1;

  if v_pkg_id is null then
    raise exception 'WNPH reconstruction batch: active source package not found for %',p_source_package_key;
  end if;

  for v_item in select value from jsonb_array_elements(p_proposals)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'WNPH reconstruction batch: each proposal must be an object';
    end if;
    if jsonb_typeof(v_item->'source_observation_ids')<>'array' then
      raise exception 'WNPH reconstruction batch: source_observation_ids must be an array';
    end if;

    select array_agg(value::uuid order by ord)
      into v_obs_ids
    from jsonb_array_elements_text(v_item->'source_observation_ids') with ordinality as x(value,ord);

    select p.* into v_existing
    from wnph.publication_source_reconstruction_proposals p
    where p.source_package_id=v_pkg_id
      and p.proposal_key=coalesce(v_item->>'proposal_key','')
      and not exists(
        select 1 from wnph.publication_source_reconstruction_proposals child
        where child.supersedes_proposal_id=p.id
      )
    order by p.created_at desc
    limit 1;

    if v_existing.id is not null then
      if v_existing.target_parent_block_id<>(v_item->>'target_parent_block_id')::uuid
         or v_existing.proposed_block_key<>coalesce(v_item->>'proposed_block_key','')
         or v_existing.proposed_ordinal<>coalesce((v_item->>'proposed_ordinal')::integer,0)
         or v_existing.proposed_block_type<>coalesce(v_item->>'proposed_block_type','paragraph')
         or coalesce(v_existing.proposed_semantic_role,'')<>coalesce(v_item->>'proposed_semantic_role','')
         or v_existing.proposed_text_content<>coalesce(v_item->>'proposed_text_content','')
         or v_existing.proposed_reading_state<>coalesce(v_item->>'proposed_reading_state','candidate')
         or v_existing.source_observation_ids<>v_obs_ids
         or v_existing.disposition<>coalesce(v_item->>'disposition','review') then
        raise exception 'WNPH reconstruction batch: active proposal_key % exists with different semantic content or lineage',v_existing.proposal_key;
      end if;
      v_proposal_id:=v_existing.id;
      v_skipped:=v_skipped+1;
    else
      insert into wnph.publication_source_reconstruction_proposals(
        source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
        proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
        source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
        proposed_source_provenance,algorithm
      ) values (
        v_pkg_id,
        coalesce(v_item->>'proposal_key',''),
        (v_item->>'target_parent_block_id')::uuid,
        coalesce(v_item->>'proposed_block_key',''),
        coalesce((v_item->>'proposed_ordinal')::integer,0),
        coalesce(v_item->>'proposed_block_type','paragraph'),
        nullif(v_item->>'proposed_semantic_role',''),
        coalesce(v_item->>'proposed_text_content',''),
        coalesce(v_item->>'proposed_reading_state','candidate'),
        v_obs_ids,
        coalesce((v_item->>'confidence')::numeric,0),
        coalesce(v_item->>'disposition','review'),
        coalesce(v_item->'review_reasons','[]'::jsonb),
        coalesce(v_item->'proposed_properties','{}'::jsonb) || jsonb_build_object(
          'reconstruction_key',p_reconstruction_key,
          'reconstruction_run_metadata',coalesce(p_run_metadata,'{}'::jsonb)
        ),
        coalesce(v_item->'proposed_source_provenance','{}'::jsonb),
        coalesce(v_item->'algorithm','{}'::jsonb)
      ) returning id into v_proposal_id;
      v_inserted:=v_inserted+1;
    end if;

    if coalesce(v_item->>'disposition','review')='auto_admit' then
      v_block_id:=wnph.promote_publication_source_reconstruction_proposal_v1(v_proposal_id);
      if v_block_id is not null then v_promoted:=v_promoted+1; end if;
    elsif coalesce(v_item->>'disposition','review')='review' then
      v_review:=v_review+1;
    else
      v_reject:=v_reject+1;
    end if;

    v_existing:=null;
    v_obs_ids:=null;
  end loop;

  return jsonb_build_object(
    'source_package_key',p_source_package_key,
    'reconstruction_key',p_reconstruction_key,
    'proposal_count',v_count,
    'inserted_proposals',v_inserted,
    'skipped_proposals',v_skipped,
    'promoted_blocks',v_promoted,
    'review_proposals',v_review,
    'rejected_proposals',v_reject
  );
end;
$function$;

revoke all on function public.wnph_commit_reconstruction_batch_v1(text,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.wnph_commit_reconstruction_batch_v1(text,text,jsonb,jsonb) to service_role;

comment on function public.wnph_commit_reconstruction_batch_v1(text,text,jsonb,jsonb) is
  'Atomic, idempotent reconstruction admission boundary. Records immutable observation-backed semantic proposals and automatically promotes only proposals explicitly classified auto_admit into candidate/usable publication source blocks.';

-- Prove promotion is usable without weakening verified custody; rollback every fixture row.
do $verify$
declare
  v_pkg uuid;
  v_parent uuid;
  v_obs uuid;
  v_result jsonb;
  v_block_count integer;
begin
  select p.id into v_pkg
  from wnph.publication_source_packages p
  where p.canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1'
  order by p.created_at desc limit 1;

  select b.id into v_parent
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg and b.block_key='dewy:chapter:1:paragraph-stream'
  order by b.created_at desc limit 1;

  select o.id into v_obs
  from wnph.publication_source_observations o
  join wnph.publication_source_assets a on a.id=o.source_asset_id
  where a.source_package_id=v_pkg and a.asset_key='dewy:loc:source-surface:0015'
  order by o.created_at desc limit 1;

  begin
    select public.wnph_commit_reconstruction_batch_v1(
      'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
      'fixture:reconstruction-promotion',
      jsonb_build_array(jsonb_build_object(
        'proposal_key','fixture:reconstruction:paragraph:999',
        'target_parent_block_id',v_parent,
        'proposed_block_key','fixture:dewy:chapter:1:paragraph:999',
        'proposed_ordinal',999,
        'proposed_block_type','paragraph',
        'proposed_semantic_role','body_paragraph',
        'proposed_text_content','Synthetic reconstruction fixture.',
        'proposed_reading_state','candidate',
        'source_observation_ids',jsonb_build_array(v_obs),
        'confidence',0.99,
        'disposition','auto_admit',
        'review_reasons','[]'::jsonb,
        'proposed_properties',jsonb_build_object('fixture',true),
        'proposed_source_provenance',jsonb_build_object(
          'text_authority','machine_reconstruction_proposal',
          'derivation_method','synthetic_reconstruction_fixture',
          'source_locators',jsonb_build_array(jsonb_build_object('printed_page',11,'source_pdf_page',15))
        ),
        'algorithm',jsonb_build_object(
          'engine','wnph_reconstruction_fixture',
          'version','1',
          'auto_admit_rule','synthetic fixture only'
        )
      )),
      jsonb_build_object('fixture',true)
    ) into v_result;

    if (v_result->>'promoted_blocks')::integer<>1 then
      raise exception 'WNPH reconstruction fixture failed to promote: %',v_result;
    end if;

    select count(*) into v_block_count
    from wnph.publication_source_blocks
    where block_key='fixture:dewy:chapter:1:paragraph:999';

    if v_block_count<>1 then
      raise exception 'WNPH reconstruction fixture block count expected 1, got %',v_block_count;
    end if;

    raise exception 'WNPH_RECONSTRUCTION_FIXTURE_ROLLBACK';
  exception when others then
    if sqlerrm<>'WNPH_RECONSTRUCTION_FIXTURE_ROLLBACK' then raise; end if;
  end;

  if exists(select 1 from wnph.publication_source_reconstruction_proposals where proposal_key='fixture:reconstruction:paragraph:999')
     or exists(select 1 from wnph.publication_source_blocks where block_key='fixture:dewy:chapter:1:paragraph:999') then
    raise exception 'WNPH reconstruction fixture rollback left surviving rows';
  end if;

  begin
    insert into wnph.publication_source_reconstruction_proposals(
      source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
      proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
      source_observation_ids,confidence,disposition,review_reasons,proposed_source_provenance,algorithm
    ) values (
      v_pkg,'fixture:review:cannot-promote',v_parent,'fixture:review:block',1000,
      'paragraph','body_paragraph','Review-only fixture.','candidate',array[v_obs],0.50,'review',
      jsonb_build_array('ambiguous paragraph boundary'),
      jsonb_build_object(
        'text_authority','machine_reconstruction_proposal',
        'derivation_method','synthetic_review_fixture',
        'source_locators',jsonb_build_array(jsonb_build_object('printed_page',11,'source_pdf_page',15))
      ),
      jsonb_build_object('engine','wnph_reconstruction_fixture','version','1')
    ) returning id into v_obs;

    perform wnph.promote_publication_source_reconstruction_proposal_v1(v_obs);
    raise exception 'WNPH reconstruction negative control unexpectedly promoted review proposal';
  exception when others then
    if sqlerrm='WNPH reconstruction negative control unexpectedly promoted review proposal' then raise; end if;
  end;

  if exists(select 1 from wnph.publication_source_reconstruction_proposals where proposal_key='fixture:review:cannot-promote') then
    raise exception 'WNPH reconstruction review fixture rollback left surviving row';
  end if;
end;
$verify$;