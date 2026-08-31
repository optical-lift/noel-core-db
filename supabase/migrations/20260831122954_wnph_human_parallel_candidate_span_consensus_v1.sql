create or replace function wnph.compare_parallel_reading_candidate_span_v1(
  p_primary_text text,
  p_candidate_text text,
  p_min_primary_words integer default 6
)
returns jsonb
language plpgsql
immutable
set search_path=pg_catalog,wnph,extensions
as $$
declare
  v_primary_norm text:=wnph.normalize_parallel_reading_text_v1(p_primary_text);
  v_candidate_norm text:=wnph.normalize_parallel_reading_text_v1(p_candidate_text);
  v_primary_words text[];
  v_candidate_words text[];
  v_primary_count integer:=0;
  v_candidate_count integer:=0;
  v_start integer;
  v_span text;
  v_sim numeric;
  v_best_sim numeric:=0;
  v_best_start integer;
  v_best_end integer;
  v_best_span text;
  v_eligible boolean:=false;
begin
  if p_min_primary_words<1 or p_min_primary_words>1000 then
    raise exception 'WNPH parallel span comparison: min primary words must be 1..1000';
  end if;

  v_primary_words:=case when v_primary_norm='' then array[]::text[] else regexp_split_to_array(v_primary_norm,' +') end;
  v_candidate_words:=case when v_candidate_norm='' then array[]::text[] else regexp_split_to_array(v_candidate_norm,' +') end;
  v_primary_count:=cardinality(v_primary_words);
  v_candidate_count:=cardinality(v_candidate_words);

  if v_primary_count=0 or v_candidate_count=0 then
    return jsonb_build_object(
      'comparison_policy','secondary_contiguous_span_v1',
      'eligible',false,
      'similarity',0,
      'primary_word_count',v_primary_count,
      'candidate_word_count',v_candidate_count,
      'candidate_span_start_word',null,
      'candidate_span_end_word',null,
      'candidate_span_word_count',0
    );
  end if;

  if v_candidate_count>=v_primary_count then
    for v_start in 1..(v_candidate_count-v_primary_count+1) loop
      v_span:=array_to_string(v_candidate_words[v_start:v_start+v_primary_count-1],' ');
      v_sim:=extensions.similarity(v_primary_norm,v_span);
      if v_best_start is null or v_sim>v_best_sim then
        v_best_sim:=v_sim;
        v_best_start:=v_start;
        v_best_end:=v_start+v_primary_count-1;
        v_best_span:=v_span;
      end if;
    end loop;
  else
    v_best_start:=1;
    v_best_end:=v_candidate_count;
    v_best_span:=v_candidate_norm;
    v_best_sim:=extensions.similarity(v_primary_norm,v_candidate_norm);
  end if;

  v_eligible:=v_primary_count>=p_min_primary_words and v_candidate_count>=v_primary_count;

  return jsonb_build_object(
    'comparison_policy','secondary_contiguous_span_v1',
    'eligible',v_eligible,
    'similarity',v_best_sim,
    'primary_word_count',v_primary_count,
    'candidate_word_count',v_candidate_count,
    'candidate_span_start_word',v_best_start,
    'candidate_span_end_word',v_best_end,
    'candidate_span_word_count',case when v_best_start is null then 0 else v_best_end-v_best_start+1 end,
    'candidate_span_normalized',v_best_span
  );
end;
$$;

comment on function wnph.compare_parallel_reading_candidate_span_v1(text,text,integer) is
'Comparison-only helper. Preserves the complete primary reading and searches only for an equal-length contiguous span inside the secondary reading. Intended to ignore secondary-witness headings/page furniture without deleting or normalizing historical source text. Auto-admission callers must honor eligible=false.';

insert into wnph.publication_source_bulk_policies(
  canonical_key,policy_version,status,consensus_mode,min_processor_families,min_proposal_confidence,
  min_parallel_similarity,qa_sample_rate,qa_min_samples,qa_max_samples,max_major_error_rate,risk_rules,notes
)
select
  'wnph:bulk-transmission:human-parallel:v1',1,'active','normalized_trigram',2,0.70,
  0.985,0.05,8,30,0,
  jsonb_build_object(
    'auto_admit_requires_empty_risk_flags',true,
    'headings_require_review',true,
    'ambiguous_page_continuity_requires_review',true,
    'illegible_or_unresolved_markers_require_review',true,
    'verified_and_adjudicated_states_remain_forensic_only',true,
    'comparison_alignment_policy','secondary_contiguous_span_v1',
    'min_primary_words_for_auto_admit',6,
    'require_transcription_consensus',true,
    'ocr_role','anomaly_evidence_only'
  ),
  'Library-scale human-parallel policy. The full primary transcription is compared against an equal-length contiguous span of each independent secondary transcription. Secondary headings or page furniture may fall outside the comparison span, but primary words can never be trimmed. OCR is auxiliary anomaly evidence only. Auto-admission remains usable-only at >=0.985 database-recomputed agreement with no risk flags; verified/adjudicated states remain forensic.'
where not exists(select 1 from wnph.publication_source_bulk_policies where canonical_key='wnph:bulk-transmission:human-parallel:v1');

update wnph.publication_source_bulk_policies
set status='retired'
where canonical_key='wnph:bulk-transmission:normalized-exact-consensus:v1'
  and not exists(
    select 1 from wnph.publication_source_bulk_batches b
    where b.policy_id=publication_source_bulk_policies.id
      and b.status not in ('closed','cancelled','failed')
  );

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
  v_primary_id uuid; v_primary_text text; v_secondary_id uuid; v_secondary_text text;
  v_min_similarity numeric; v_span jsonb; v_span_similarity numeric; v_all_eligible boolean:=true;
  v_comparison_policy text; v_min_primary_words integer; v_supplied_similarity numeric;
  v_transcription_count integer;
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

      if coalesce((v_policy.risk_rules->>'require_transcription_consensus')::boolean,false) then
        select count(*) into v_transcription_count
        from wnph.publication_source_observations o
        where o.id=any(v_consensus_ids)
          and (o.derivation_method ilike '%transcription%' or o.source_format ilike '%transcript%')
          and not exists(select 1 from wnph.publication_source_observations child where child.supersedes_observation_id=o.id);
        if v_transcription_count<>v_consensus_count then raise exception 'WNPH bulk reconstruction: human-parallel policy requires transcription evidence for every consensus reading'; end if;
      end if;

      if v_policy.consensus_mode='normalized_exact' and v_normalized_readings<>1 then raise exception 'WNPH bulk reconstruction: normalized readings disagree; auto-admit refused'; end if;
      if v_policy.consensus_mode='normalized_trigram' then
        v_primary_id:=nullif(new.proposed_properties->>'bulk_primary_observation_id','')::uuid;
        if v_primary_id is null or not (v_primary_id=any(v_consensus_ids)) then raise exception 'WNPH bulk reconstruction: normalized_trigram requires a primary observation within consensus evidence'; end if;
        select text_candidate into v_primary_text from wnph.publication_source_observations where id=v_primary_id;
        v_comparison_policy:=coalesce(v_policy.risk_rules->>'comparison_alignment_policy','full_normalized_trigram_v1');
        if coalesce(new.proposed_properties->>'bulk_comparison_alignment_policy',v_comparison_policy)<>v_comparison_policy then raise exception 'WNPH bulk reconstruction: proposal comparison policy does not match active bulk policy'; end if;
        v_supplied_similarity:=nullif(new.proposed_properties->>'bulk_parallel_similarity','')::numeric;

        if v_comparison_policy='secondary_contiguous_span_v1' then
          v_min_primary_words:=coalesce((v_policy.risk_rules->>'min_primary_words_for_auto_admit')::integer,6);
          v_min_similarity:=1;
          foreach v_secondary_id in array v_consensus_ids loop
            if v_secondary_id=v_primary_id then continue; end if;
            select text_candidate into v_secondary_text from wnph.publication_source_observations where id=v_secondary_id;
            v_span:=wnph.compare_parallel_reading_candidate_span_v1(v_primary_text,v_secondary_text,v_min_primary_words);
            v_span_similarity:=coalesce((v_span->>'similarity')::numeric,0);
            if not coalesce((v_span->>'eligible')::boolean,false) then v_all_eligible:=false; end if;
            v_min_similarity:=least(v_min_similarity,v_span_similarity);
          end loop;
          if not v_all_eligible then raise exception 'WNPH bulk reconstruction: comparison span is not eligible for auto-admission'; end if;
        else
          select min(extensions.similarity(wnph.normalize_parallel_reading_text_v1(v_primary_text),wnph.normalize_parallel_reading_text_v1(o.text_candidate))) into v_min_similarity
          from wnph.publication_source_observations o where o.id=any(v_consensus_ids) and o.id<>v_primary_id;
        end if;

        if v_min_similarity is null or v_min_similarity<v_policy.min_parallel_similarity then raise exception 'WNPH bulk reconstruction: database-recomputed parallel similarity % below policy floor %',v_min_similarity,v_policy.min_parallel_similarity; end if;
        if v_supplied_similarity is null or abs(v_supplied_similarity-v_min_similarity)>0.0005 then raise exception 'WNPH bulk reconstruction: supplied parallel similarity % does not match database recomputation %',v_supplied_similarity,v_min_similarity; end if;
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

create or replace function wnph.run_bulk_parallel_reconstruction_v1(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph,public,extensions
as $$
declare
  v_batch wnph.publication_source_bulk_batches%rowtype; v_policy wnph.publication_source_bulk_policies%rowtype;
  v_asset_key text; v_asset wnph.publication_source_assets%rowtype;
  v_ws wnph.publication_source_observations%rowtype; v_human wnph.publication_source_observations%rowtype; v_ia wnph.publication_source_observations%rowtype;
  v_proposals jsonb:='[]'::jsonb; v_item jsonb; v_reasons jsonb; v_risks jsonb; v_span jsonb;
  v_sim numeric; v_ia_sim numeric; v_conf numeric; v_ord integer; v_n integer:=0;
  v_page integer; v_is_first boolean:=true; v_last_ws wnph.publication_source_observations%rowtype; v_result jsonb; v_reconstruction_key text;
  v_min_primary_words integer; v_primary_word_count integer; v_comparison_eligible boolean;
  v_source_ids jsonb; v_consensus_ids jsonb;
begin
  select * into v_batch from wnph.publication_source_bulk_batches where id=p_batch_id for update;
  if v_batch.id is null then raise exception 'WNPH bulk reconstruction: batch not found'; end if;
  select * into v_policy from wnph.publication_source_bulk_policies where id=v_batch.policy_id and status='active';
  if v_policy.id is null then raise exception 'WNPH bulk reconstruction: active policy not found'; end if;
  if v_batch.status not in ('evidence_ready','planned') then raise exception 'WNPH bulk reconstruction: batch status % is not runnable',v_batch.status; end if;
  if coalesce(v_policy.risk_rules->>'ocr_role','')<>'anomaly_evidence_only' then raise exception 'WNPH bulk reconstruction: runner requires a policy that explicitly keeps OCR out of consensus'; end if;
  update wnph.publication_source_bulk_batches set status='running' where id=v_batch.id;
  select coalesce(max(b.ordinal),0)+1 into v_ord from wnph.publication_source_blocks b where b.parent_block_id=v_batch.target_parent_block_id and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
  v_reconstruction_key:='bulk:'||v_batch.batch_key||':v1';
  v_min_primary_words:=coalesce((v_policy.risk_rules->>'min_primary_words_for_auto_admit')::integer,6);

  foreach v_asset_key in array v_batch.asset_keys loop
    select a.* into v_asset from wnph.publication_source_assets a where a.source_package_id=v_batch.source_package_id and a.asset_key=v_asset_key and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id) order by a.created_at desc limit 1;
    if v_asset.id is null then raise exception 'WNPH bulk reconstruction: active asset % not found',v_asset_key; end if;
    v_page:=coalesce((v_asset.source_locator->>'sequence_index')::integer,0);
    select o.* into v_last_ws from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage' and o.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.ordinal desc limit 1;
    for v_ws in
      select o.* from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage' and o.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.ordinal,o.created_at
    loop
      select o.* into v_human
      from wnph.publication_source_observations o
      where o.source_asset_id=v_asset.id
        and o.metadata->>'aligned_to_observation_id'=v_ws.id::text
        and (o.derivation_method ilike '%transcription%' or o.source_format ilike '%transcript%')
        and coalesce(o.processor->>'provider','')<>'Wikisource'
        and coalesce(o.processor->>'provider','')<>'Internet Archive'
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id)
      order by coalesce((o.metadata->>'alignment_similarity')::numeric,0) desc,o.created_at desc limit 1;

      select o.* into v_ia
      from wnph.publication_source_observations o
      where o.source_asset_id=v_asset.id
        and o.metadata->>'aligned_to_observation_id'=v_ws.id::text
        and o.metadata->>'reading_family'='ia_djvu_ocr_aligned'
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id)
      order by o.created_at desc limit 1;

      v_reasons:='[]'::jsonb; v_risks:='[]'::jsonb; v_span=null; v_sim:=0; v_ia_sim:=null; v_comparison_eligible:=false; v_primary_word_count:=0;
      if v_human.id is null then
        v_risks:=v_risks||'"missing_human_parallel_reading"'::jsonb;
      else
        v_span:=wnph.compare_parallel_reading_candidate_span_v1(v_ws.text_candidate,v_human.text_candidate,v_min_primary_words);
        v_sim:=coalesce((v_span->>'similarity')::numeric,0);
        v_comparison_eligible:=coalesce((v_span->>'eligible')::boolean,false);
        v_primary_word_count:=coalesce((v_span->>'primary_word_count')::integer,0);
        if not v_comparison_eligible then v_risks:=v_risks||'"comparison_span_ineligible"'::jsonb; end if;
      end if;

      if v_ia.id is not null then
        v_ia_sim:=extensions.similarity(wnph.normalize_parallel_reading_text_v1(v_ws.text_candidate),wnph.normalize_parallel_reading_text_v1(v_ia.text_candidate));
      end if;
      if position('[ILLEGIBLE]' in upper(coalesce(v_ws.text_candidate,'')))>0 or position('[ILLEGIBLE]' in upper(coalesce(v_human.text_candidate,'')))>0 then v_risks:=v_risks||'"illegible_marker"'::jsonb; end if;
      if coalesce(v_ws.text_candidate,'') ~ '(\{\||\|-|rowspan|colspan|style=|\[\[Page:)' then v_risks:=v_risks||'"unresolved_transcription_markup"'::jsonb; end if;
      if v_is_first and coalesce(v_batch.stats->>'starts_inside_prior_semantic_unit','false')::boolean then v_risks:=v_risks||'"batch_starts_inside_prior_semantic_unit"'::jsonb; end if;
      if v_ws.id=v_last_ws.id and btrim(v_ws.text_candidate) !~ '[.!?][”’"'')\]]?$' then v_risks:=v_risks||'"cross_page_semantic_join_required"'::jsonb; end if;
      if v_human.id is not null and v_sim<v_policy.min_parallel_similarity then v_risks:=v_risks||'"parallel_reading_disagreement"'::jsonb; end if;

      v_conf:=least(coalesce(v_ws.confidence,0),coalesce(v_human.confidence,0),coalesce(v_sim,0));
      if v_conf<v_policy.min_proposal_confidence then v_risks:=v_risks||'"confidence_below_bulk_policy_floor"'::jsonb; end if;
      if jsonb_array_length(v_risks)>0 then v_reasons:=v_risks; end if;

      v_consensus_ids:=case when v_human.id is null then jsonb_build_array(v_ws.id) else jsonb_build_array(v_ws.id,v_human.id) end;
      v_source_ids:=v_consensus_ids;
      if v_ia.id is not null then v_source_ids:=v_source_ids||jsonb_build_array(v_ia.id); end if;

      v_n:=v_n+1;
      v_item:=jsonb_build_object(
        'proposal_key',v_reconstruction_key||':'||lpad(v_n::text,5,'0'),
        'target_parent_block_id',v_batch.target_parent_block_id,
        'proposed_block_key',v_batch.batch_key||':paragraph:'||lpad(v_n::text,5,'0'),
        'proposed_ordinal',v_ord,'proposed_block_type','paragraph','proposed_semantic_role','historical_prose',
        'proposed_text_content',v_ws.text_candidate,'proposed_reading_state','usable',
        'source_observation_ids',v_source_ids,
        'confidence',v_conf,'disposition',case when jsonb_array_length(v_risks)=0 then 'auto_admit' else 'review' end,'review_reasons',v_reasons,
        'proposed_properties',jsonb_build_object(
          'bulk_batch_key',v_batch.batch_key,'bulk_risk_flags',v_risks,'bulk_parallel_similarity',v_sim,
          'bulk_primary_observation_id',v_ws.id,'bulk_consensus_observation_ids',v_consensus_ids,
          'bulk_comparison_alignment_policy','secondary_contiguous_span_v1',
          'bulk_secondary_span_start_word',case when v_span is null then null else (v_span->>'candidate_span_start_word')::integer end,
          'bulk_secondary_span_end_word',case when v_span is null then null else (v_span->>'candidate_span_end_word')::integer end,
          'bulk_primary_word_count',v_primary_word_count,
          'bulk_human_parallel_observation_id',v_human.id,
          'bulk_ocr_anomaly_observation_id',v_ia.id,
          'bulk_ocr_anomaly_similarity',v_ia_sim,
          'source_surface_keys',jsonb_build_array(v_asset.asset_key),'scan_page',v_page
        ),
        'proposed_source_provenance',jsonb_build_object(
          'text_authority','parallel_human_transcription_consensus_candidate_from_governed_source_observations',
          'derivation_method','wikisource_primary_compared_to_contiguous_span_of_independent_human_transcription_v1',
          'verification_status','machine_collated_not_forensically_verified','bulk_policy_key',v_policy.canonical_key,
          'source_locators',jsonb_build_array(jsonb_build_object('source_asset_id',v_asset.id,'source_asset_key',v_asset.asset_key,'sequence_index',v_page,'image_uri',v_asset.source_locator->>'image_uri'))
        ),
        'algorithm',jsonb_build_object('engine','wnph_bulk_parallel_reconstructor','version','2','auto_admit_rule','database-enforced human-parallel policy: complete primary reading preserved; each independent transcription compared by database to an equal-length contiguous secondary span; >= similarity floor, confidence floor, and zero unresolved risk flags. OCR is anomaly evidence only; verified/adjudicated states are never produced.')
      );
      v_proposals:=v_proposals||jsonb_build_array(v_item); v_ord:=v_ord+1; v_is_first:=false;
    end loop;
  end loop;
  if jsonb_array_length(v_proposals)=0 then raise exception 'WNPH bulk reconstruction: no Wikisource reading regions available'; end if;
  v_result:=public.wnph_commit_reconstruction_batch_v1((select canonical_key from wnph.publication_source_packages where id=v_batch.source_package_id),v_reconstruction_key,v_proposals,jsonb_build_object('bulk_batch_key',v_batch.batch_key,'bulk_policy_key',v_policy.canonical_key,'worker','wnph.run_bulk_parallel_reconstruction_v1','worker_version',2));
  update wnph.publication_source_bulk_batches set status=case when coalesce((v_result->>'promoted_blocks')::integer,0)>0 then 'qa_pending' else 'running' end,qa_status=case when coalesce((v_result->>'promoted_blocks')::integer,0)>0 then 'pending' else 'not_started' end,stats=stats||v_result where id=v_batch.id;
  if coalesce((v_result->>'promoted_blocks')::integer,0)>0 then perform wnph.seed_bulk_qa_samples_v1(v_batch.id); end if;
  return v_result;
end;
$$;

revoke execute on function wnph.compare_parallel_reading_candidate_span_v1(text,text,integer) from public,anon,authenticated;
revoke execute on function wnph.run_bulk_parallel_reconstruction_v1(uuid) from public,anon,authenticated;