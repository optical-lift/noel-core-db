create extension if not exists pg_trgm with schema extensions;

alter table wnph.publication_source_bulk_policies
  add column if not exists min_parallel_similarity numeric;

alter table wnph.publication_source_bulk_policies
  drop constraint if exists publication_source_bulk_policies_consensus_mode_check;
alter table wnph.publication_source_bulk_policies
  add constraint publication_source_bulk_policies_consensus_mode_check
  check (consensus_mode in ('normalized_exact','normalized_trigram'));

update wnph.publication_source_bulk_policies
set consensus_mode='normalized_trigram', min_parallel_similarity=0.985,
    notes='Library-scale default. A primary reading may auto-admit to usable only when at least two independent processor families are aligned to the same semantic unit and the database-recomputed normalized trigram similarity is at least 0.985. Any substantive disagreement remains review. Statistical QA is mandatory before batch closure.'
where canonical_key='wnph:bulk-transmission:normalized-exact-consensus:v1';

alter table wnph.publication_source_bulk_policies
  alter column min_parallel_similarity set not null;
alter table wnph.publication_source_bulk_policies
  add constraint publication_source_bulk_policies_min_parallel_similarity_check
  check (min_parallel_similarity>=0 and min_parallel_similarity<=1);

create or replace function wnph.validate_publication_source_reconstruction_proposal_v1()
returns trigger
language plpgsql
set search_path=pg_catalog,wnph,extensions
as $$
declare
  v_parent_package uuid; v_obs_id uuid; v_obs_package uuid;
  v_old wnph.publication_source_reconstruction_proposals%rowtype; v_distinct_obs integer;
  v_policy wnph.publication_source_bulk_policies%rowtype; v_bulk_policy_key text;
  v_consensus_ids uuid[]; v_consensus_count integer; v_processor_families integer;
  v_normalized_readings integer; v_nonempty_normalized integer; v_risk_flags jsonb;
  v_primary_id uuid; v_primary_text text; v_min_similarity numeric;
begin
  if jsonb_typeof(new.review_reasons)<>'array' then raise exception 'WNPH reconstruction proposal: review_reasons must be an array'; end if;
  if jsonb_typeof(new.proposed_properties)<>'object' or jsonb_typeof(new.proposed_source_provenance)<>'object' or jsonb_typeof(new.algorithm)<>'object' then raise exception 'WNPH reconstruction proposal: properties, provenance and algorithm must be objects'; end if;
  select b.source_package_id into v_parent_package from wnph.publication_source_blocks b where b.id=new.target_parent_block_id and not exists(select 1 from wnph.publication_source_blocks child where child.supersedes_block_id=b.id);
  if v_parent_package is null or v_parent_package<>new.source_package_id then raise exception 'WNPH reconstruction proposal: target parent must be an active block in the same source package'; end if;
  select count(distinct x) into v_distinct_obs from unnest(new.source_observation_ids) x;
  if v_distinct_obs<>cardinality(new.source_observation_ids) then raise exception 'WNPH reconstruction proposal: source_observation_ids may not contain duplicates'; end if;
  foreach v_obs_id in array new.source_observation_ids loop
    select a.source_package_id into v_obs_package from wnph.publication_source_observations o join wnph.publication_source_assets a on a.id=o.source_asset_id where o.id=v_obs_id and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
    if v_obs_package is null or v_obs_package<>new.source_package_id then raise exception 'WNPH reconstruction proposal: observation % must be active and belong to the same source package',v_obs_id; end if;
  end loop;
  if jsonb_typeof(new.proposed_source_provenance->'source_locators')<>'array' or jsonb_array_length(new.proposed_source_provenance->'source_locators')=0 then raise exception 'WNPH reconstruction proposal: source_locators are required'; end if;
  if coalesce(new.proposed_source_provenance->>'text_authority','')='' then raise exception 'WNPH reconstruction proposal: text_authority is required'; end if;
  if coalesce(new.proposed_source_provenance->>'derivation_method','')='' then raise exception 'WNPH reconstruction proposal: derivation_method is required'; end if;
  if coalesce(new.algorithm->>'engine','')='' or coalesce(new.algorithm->>'version','')='' then raise exception 'WNPH reconstruction proposal: algorithm requires engine and version'; end if;
  if new.disposition='auto_admit' then
    if jsonb_array_length(new.review_reasons)<>0 then raise exception 'WNPH reconstruction proposal: auto_admit may not carry review reasons'; end if;
    if coalesce(new.algorithm->>'auto_admit_rule','')='' then raise exception 'WNPH reconstruction proposal: auto_admit requires an explicit algorithm auto_admit_rule'; end if;
  elsif new.disposition='review' and jsonb_array_length(new.review_reasons)=0 then raise exception 'WNPH reconstruction proposal: review disposition requires at least one review reason'; end if;

  v_bulk_policy_key:=nullif(new.proposed_source_provenance->>'bulk_policy_key','');
  if v_bulk_policy_key is not null then
    select * into v_policy from wnph.publication_source_bulk_policies where canonical_key=v_bulk_policy_key and status='active';
    if v_policy.id is null then raise exception 'WNPH bulk reconstruction: active policy % not found',v_bulk_policy_key; end if;
    if jsonb_typeof(coalesce(new.proposed_properties->'bulk_risk_flags','[]'::jsonb))<>'array' then raise exception 'WNPH bulk reconstruction: bulk_risk_flags must be an array'; end if;
    v_risk_flags:=coalesce(new.proposed_properties->'bulk_risk_flags','[]'::jsonb);
    if new.disposition='auto_admit' then
      if new.proposed_reading_state<>'usable' then raise exception 'WNPH bulk reconstruction: auto-admit under a bulk policy must promote only usable text'; end if;
      if new.confidence<v_policy.min_proposal_confidence then raise exception 'WNPH bulk reconstruction: confidence % below policy floor %',new.confidence,v_policy.min_proposal_confidence; end if;
      if jsonb_array_length(v_risk_flags)<>0 then raise exception 'WNPH bulk reconstruction: auto-admit forbidden while risk flags remain'; end if;
      if jsonb_typeof(new.proposed_properties->'bulk_consensus_observation_ids')<>'array' then raise exception 'WNPH bulk reconstruction: auto-admit requires bulk_consensus_observation_ids'; end if;
      select array_agg(value::uuid order by ord) into v_consensus_ids from jsonb_array_elements_text(new.proposed_properties->'bulk_consensus_observation_ids') with ordinality x(value,ord);
      v_consensus_count:=coalesce(cardinality(v_consensus_ids),0);
      if v_consensus_count<v_policy.min_processor_families then raise exception 'WNPH bulk reconstruction: consensus evidence count % below policy minimum %',v_consensus_count,v_policy.min_processor_families; end if;
      if exists(select 1 from unnest(v_consensus_ids) x where not (x=any(new.source_observation_ids))) then raise exception 'WNPH bulk reconstruction: consensus evidence must be contained in source_observation_ids'; end if;
      select count(distinct coalesce(o.processor->>'provider','')||':'||coalesce(o.processor->>'engine','')),count(distinct wnph.normalize_parallel_reading_text_v1(o.text_candidate)),count(*) filter(where wnph.normalize_parallel_reading_text_v1(o.text_candidate)<>'')
      into v_processor_families,v_normalized_readings,v_nonempty_normalized
      from wnph.publication_source_observations o join wnph.publication_source_assets a on a.id=o.source_asset_id
      where o.id=any(v_consensus_ids) and a.source_package_id=new.source_package_id and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
      if v_nonempty_normalized<>v_consensus_count then raise exception 'WNPH bulk reconstruction: every consensus observation must contain text'; end if;
      if v_processor_families<v_policy.min_processor_families then raise exception 'WNPH bulk reconstruction: % processor families below policy minimum %',v_processor_families,v_policy.min_processor_families; end if;
      if v_policy.consensus_mode='normalized_exact' and v_normalized_readings<>1 then raise exception 'WNPH bulk reconstruction: normalized readings disagree; auto-admit refused'; end if;
      if v_policy.consensus_mode='normalized_trigram' then
        v_primary_id:=nullif(new.proposed_properties->>'bulk_primary_observation_id','')::uuid;
        if v_primary_id is null or not (v_primary_id=any(v_consensus_ids)) then raise exception 'WNPH bulk reconstruction: normalized_trigram requires a primary observation within consensus evidence'; end if;
        select wnph.normalize_parallel_reading_text_v1(text_candidate) into v_primary_text from wnph.publication_source_observations where id=v_primary_id;
        select min(extensions.similarity(v_primary_text,wnph.normalize_parallel_reading_text_v1(o.text_candidate))) into v_min_similarity
        from wnph.publication_source_observations o where o.id=any(v_consensus_ids) and o.id<>v_primary_id;
        if v_min_similarity is null or v_min_similarity<v_policy.min_parallel_similarity then raise exception 'WNPH bulk reconstruction: database-recomputed parallel similarity % below policy floor %',v_min_similarity,v_policy.min_parallel_similarity; end if;
      end if;
    end if;
  end if;

  if new.supersedes_proposal_id is not null then
    select * into v_old from wnph.publication_source_reconstruction_proposals where id=new.supersedes_proposal_id;
    if v_old.id is null or v_old.source_package_id<>new.source_package_id or v_old.proposal_key<>new.proposal_key or v_old.proposed_block_key<>new.proposed_block_key then raise exception 'WNPH reconstruction proposal: supersession must preserve source package, proposal_key and proposed_block_key'; end if;
    if exists(select 1 from wnph.publication_source_reconstruction_proposals p where p.supersedes_proposal_id=v_old.id) then raise exception 'WNPH reconstruction proposal: supersession fork is not allowed'; end if;
  elsif exists(select 1 from wnph.publication_source_reconstruction_proposals p where p.source_package_id=new.source_package_id and p.proposal_key=new.proposal_key and not exists(select 1 from wnph.publication_source_reconstruction_proposals child where child.supersedes_proposal_id=p.id)) then raise exception 'WNPH reconstruction proposal: duplicate active proposal_key %',new.proposal_key; end if;
  return new;
end;
$$;