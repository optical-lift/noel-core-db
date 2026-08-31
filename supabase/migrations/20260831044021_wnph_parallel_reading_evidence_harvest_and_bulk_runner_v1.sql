create or replace function wnph.join_djvu_paragraph_words_v1(p_para xml)
returns text
language plpgsql
immutable
set search_path=pg_catalog,wnph
as $$
declare
  v_nodes xml[]; v_node xml; v_word text; v_out text:='';
begin
  v_nodes:=xpath('.//WORD/text()',p_para);
  foreach v_node in array v_nodes loop
    v_word:=btrim(v_node::text);
    if v_word='' then continue; end if;
    if v_out='' then v_out:=v_word;
    elsif right(v_out,1) in ('-','⸗') then v_out:=left(v_out,length(v_out)-1)||v_word;
    elsif v_word ~ '^[,.;:!?)]' then v_out:=v_out||v_word;
    else v_out:=v_out||' '||v_word;
    end if;
  end loop;
  return btrim(regexp_replace(v_out,'[[:space:]]+',' ','g'));
end;
$$;

create or replace function wnph.djvu_paragraph_confidence_v1(p_para xml)
returns numeric
language plpgsql
immutable
set search_path=pg_catalog,wnph
as $$
declare
  v_nodes xml[]; v_node xml; v_sum numeric:=0; v_n integer:=0; v numeric;
begin
  v_nodes:=xpath('.//WORD/@x-confidence',p_para);
  foreach v_node in array v_nodes loop
    begin v:=greatest(0,least(100,(v_node::text)::numeric)); exception when others then v:=null; end;
    if v is not null then v_sum:=v_sum+v; v_n:=v_n+1; end if;
  end loop;
  if v_n=0 then return null; end if;
  return round((v_sum/v_n)/100,4);
end;
$$;

create or replace function wnph.clean_wikisource_proofreadpage_v1(p_wikitext text)
returns text
language plpgsql
immutable
set search_path=pg_catalog,wnph
as $$
declare v text:=coalesce(p_wikitext,'');
begin
  v:=regexp_replace(v,'<noinclude>(.|\n)*?</noinclude>','','g');
  v:=regexp_replace(v,'\{\{mufi\|&#42843;\}\}','ꝛ','gi');
  v:=regexp_replace(v,'\{\{mufi\|&#xA75B;\}\}','ꝛ','gi');
  v:=regexp_replace(v,'\{\{illegible([^}]*)\}\}','[ILLEGIBLE]','gi');
  v:=replace(v,'&#42843;','ꝛ');
  v:=replace(v,'&#xA75B;','ꝛ');
  v:=replace(v,'&amp;','&');
  v:=replace(v,'&nbsp;',' ');
  v:=regexp_replace(v,'\[\[[^]|]+\|([^]]+)\]\]','\1','g');
  v:=regexp_replace(v,'\[\[([^]]+)\]\]','\1','g');
  v:=replace(v,'''','');
  v:=regexp_replace(v,'<[^>]+>','','g');
  v:=regexp_replace(v,'\{\{[^{}]*\}\}','','g');
  v:=regexp_replace(v,'\{\{[^{}]*\}\}','','g');
  v:=regexp_replace(v,E'\r\n?',E'\n','g');
  v:=regexp_replace(v,'[ \t]+',' ','g');
  v:=regexp_replace(v,E' *\n *',E'\n','g');
  v:=regexp_replace(v,E'\n{3,}',E'\n\n','g');
  return btrim(v);
end;
$$;

create or replace function wnph.harvest_parallel_reading_evidence_v1(
  p_source_package_key text,
  p_internet_archive_identifier text,
  p_wikisource_file_title text,
  p_start_page integer,
  p_end_page integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph,extensions
as $$
declare
  v_pkg_id uuid; v_xml_text text; v_doc xml; v_page integer; v_asset wnph.publication_source_assets%rowtype;
  v_obj xml; v_paras xml[]; v_para xml; v_text text; v_conf numeric; v_ord integer; v_inserted_ia integer:=0;
  v_api text; v_resp extensions.http_response; v_j jsonb; v_raw text; v_clean text; v_quality integer; v_piece text; v_inserted_ws integer:=0;
  v_ws wnph.publication_source_observations%rowtype; v_best_text text; v_best_conf numeric; v_best_ids uuid[]; v_best_sim numeric; v_inserted_align integer:=0;
  v_key text; v_existing uuid;
begin
  if p_start_page<1 or p_end_page<p_start_page then raise exception 'WNPH parallel harvest: invalid page range'; end if;
  select p.id into v_pkg_id from wnph.publication_source_packages p where p.canonical_key=p_source_package_key and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id) order by p.created_at desc limit 1;
  if v_pkg_id is null then raise exception 'WNPH parallel harvest: active source package % not found',p_source_package_key; end if;

  v_resp:=extensions.http_get(('https://archive.org/download/'||extensions.urlencode(p_internet_archive_identifier)||'/'||extensions.urlencode(p_internet_archive_identifier||'_djvu.xml'))::varchar);
  if v_resp.status<>200 then raise exception 'WNPH parallel harvest: Internet Archive DjVu XML fetch returned %',v_resp.status; end if;
  v_xml_text:=v_resp.content; v_doc:=xmlparse(document v_xml_text);
  if coalesce(array_length(xpath('//OBJECT',v_doc),1),0)<p_end_page then raise exception 'WNPH parallel harvest: IA OCR has fewer source surfaces than requested'; end if;

  for v_page in p_start_page..p_end_page loop
    select a.* into v_asset from wnph.publication_source_assets a
    where a.source_package_id=v_pkg_id and (a.source_locator->>'sequence_index')::integer=v_page
      and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id)
    order by a.created_at desc limit 1;
    if v_asset.id is null then raise exception 'WNPH parallel harvest: active source surface % missing',v_page; end if;

    v_obj:=(xpath(format('(//OBJECT)[%s]',v_page),v_doc))[1];
    v_paras:=xpath('.//PARAGRAPH',v_obj); v_ord:=0;
    foreach v_para in array v_paras loop
      v_text:=wnph.join_djvu_paragraph_words_v1(v_para);
      if coalesce(v_text,'')='' then continue; end if;
      v_ord:=v_ord+1; v_conf:=wnph.djvu_paragraph_confidence_v1(v_para);
      v_key:=format('bulk:ia-djvu-xml:page:%s:region:%s:v1',lpad(v_page::text,4,'0'),lpad(v_ord::text,3,'0'));
      select o.id into v_existing from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.observation_key=v_key and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) limit 1;
      if v_existing is null then
        insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
        values(v_asset.id,v_key,'region',v_ord,v_text,'surface',v_conf,'internet_archive_djvu_xml_paragraph_import','djvu_xml',
          jsonb_build_object('provider','Internet Archive','engine','DjVuXML OCR','version','archive-derivative'),
          jsonb_build_object('identifier',p_internet_archive_identifier,'ocr_file',p_internet_archive_identifier||'_djvu.xml','scan_page',v_page),
          jsonb_build_object('canonical_authority',false,'bulk_evidence',true,'reading_family','ia_djvu_ocr','promotion_allowed',false));
        v_inserted_ia:=v_inserted_ia+1;
      end if;
    end loop;

    v_api:='https://en.wikisource.org/w/api.php?action=parse&page='||extensions.urlencode(('Page:'||p_wikisource_file_title||'/'||v_page)::varchar)||'&prop=wikitext&format=json&formatversion=2';
    v_resp:=extensions.http_get(v_api::varchar);
    if v_resp.status<>200 then raise exception 'WNPH parallel harvest: Wikisource page % returned %',v_page,v_resp.status; end if;
    v_j:=v_resp.content::jsonb; v_raw:=v_j#>>'{parse,wikitext}';
    if v_raw is null then raise exception 'WNPH parallel harvest: Wikisource page % lacked wikitext',v_page; end if;
    begin v_quality:=(regexp_match(v_raw,'<pagequality level="([0-9]+)"'))[1]::integer; exception when others then v_quality:=null; end;
    v_clean:=wnph.clean_wikisource_proofreadpage_v1(v_raw); v_ord:=0;
    for v_piece in select btrim(x) from regexp_split_to_table(v_clean,E'\n[ \t]*\n+') x where btrim(x)<>'' loop
      v_ord:=v_ord+1;
      v_key:=format('bulk:wikisource-proofreadpage:page:%s:region:%s:v1',lpad(v_page::text,4,'0'),lpad(v_ord::text,3,'0'));
      select o.id into v_existing from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.observation_key=v_key and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) limit 1;
      if v_existing is null then
        insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
        values(v_asset.id,v_key,'region',v_ord,regexp_replace(v_piece,E'\n+',' ','g'),'surface',case v_quality when 4 then .97 when 3 then .90 when 2 then .72 when 1 then .50 else .65 end,
          'wikisource_proofreadpage_transcription_import','proofreadpage_wikitext',jsonb_build_object('provider','Wikisource','engine','ProofreadPage','version','mediawiki-api'),
          jsonb_build_object('page_title','Page:'||p_wikisource_file_title||'/'||v_page,'api_uri',v_api,'scan_page',v_page,'page_quality_level',v_quality),
          jsonb_build_object('canonical_authority',false,'bulk_evidence',true,'reading_family','wikisource_proofreadpage','promotion_allowed',false,'page_quality_level',v_quality));
        v_inserted_ws:=v_inserted_ws+1;
      end if;
    end loop;

    for v_ws in
      select o.* from wnph.publication_source_observations o
      where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage'
        and o.metadata->>'bulk_evidence'='true'
        and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id)
      order by o.ordinal,o.created_at
    loop
      select q.window_text,q.window_conf,q.obs_ids,q.sim into v_best_text,v_best_conf,v_best_ids,v_best_sim
      from (
        select string_agg(o.text_candidate,' ' order by o.ordinal) window_text,
               min(o.confidence) window_conf,
               array_agg(o.id order by o.ordinal) obs_ids,
               extensions.similarity(wnph.normalize_parallel_reading_text_v1(v_ws.text_candidate),wnph.normalize_parallel_reading_text_v1(string_agg(o.text_candidate,' ' order by o.ordinal))) sim,
               s.start_ord,k.len
        from (select distinct ordinal start_ord from wnph.publication_source_observations where source_asset_id=v_asset.id and processor->>'provider'='Internet Archive' and processor->>'engine'='DjVuXML OCR' and metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations cc where cc.supersedes_observation_id=publication_source_observations.id)) s
        cross join generate_series(1,8) k(len)
        join wnph.publication_source_observations o on o.source_asset_id=v_asset.id and o.processor->>'provider'='Internet Archive' and o.processor->>'engine'='DjVuXML OCR' and o.metadata->>'bulk_evidence'='true' and o.ordinal between s.start_ord and s.start_ord+k.len-1 and not exists(select 1 from wnph.publication_source_observations cc where cc.supersedes_observation_id=o.id)
        group by s.start_ord,k.len
        having count(*)=k.len
      ) q order by q.sim desc,abs(q.start_ord-coalesce(v_ws.ordinal,1)),q.len asc limit 1;
      if v_best_text is null then continue; end if;
      v_key:=format('bulk:ia-aligned-to-wikisource:page:%s:region:%s:v1',lpad(v_page::text,4,'0'),lpad(coalesce(v_ws.ordinal,0)::text,3,'0'));
      select o.id into v_existing from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.observation_key=v_key and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) limit 1;
      if v_existing is null then
        insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
        values(v_asset.id,v_key,'region',v_ws.ordinal,v_best_text,'surface',v_best_conf,'contiguous_ia_djvu_region_window_alignment_by_normalized_trigram_v1','aligned_djvu_xml_window',
          jsonb_build_object('provider','Internet Archive','engine','DjVuXML OCR aligned window','version','1'),
          jsonb_build_object('identifier',p_internet_archive_identifier,'scan_page',v_page,'aligned_to_observation_id',v_ws.id),
          jsonb_build_object('canonical_authority',false,'bulk_evidence',true,'reading_family','ia_djvu_ocr_aligned','promotion_allowed',false,'aligned_to_observation_id',v_ws.id,'source_observation_ids',to_jsonb(v_best_ids),'alignment_similarity',v_best_sim));
        v_inserted_align:=v_inserted_align+1;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('source_package_key',p_source_package_key,'page_start',p_start_page,'page_end',p_end_page,'ia_regions_inserted',v_inserted_ia,'wikisource_regions_inserted',v_inserted_ws,'aligned_ia_regions_inserted',v_inserted_align);
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
  v_asset_key text; v_asset wnph.publication_source_assets%rowtype; v_ws wnph.publication_source_observations%rowtype; v_ia wnph.publication_source_observations%rowtype;
  v_proposals jsonb:='[]'::jsonb; v_item jsonb; v_reasons jsonb; v_risks jsonb; v_sim numeric; v_conf numeric; v_ord integer; v_n integer:=0;
  v_page integer; v_is_first boolean:=true; v_last_ws wnph.publication_source_observations%rowtype; v_result jsonb; v_reconstruction_key text;
begin
  select * into v_batch from wnph.publication_source_bulk_batches where id=p_batch_id for update;
  if v_batch.id is null then raise exception 'WNPH bulk reconstruction: batch not found'; end if;
  select * into v_policy from wnph.publication_source_bulk_policies where id=v_batch.policy_id and status='active';
  if v_policy.id is null then raise exception 'WNPH bulk reconstruction: active policy not found'; end if;
  if v_batch.status not in ('evidence_ready','planned') then raise exception 'WNPH bulk reconstruction: batch status % is not runnable',v_batch.status; end if;
  update wnph.publication_source_bulk_batches set status='running' where id=v_batch.id;
  select coalesce(max(b.ordinal),0)+1 into v_ord from wnph.publication_source_blocks b where b.parent_block_id=v_batch.target_parent_block_id and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id);
  v_reconstruction_key:='bulk:'||v_batch.batch_key||':v1';

  foreach v_asset_key in array v_batch.asset_keys loop
    select a.* into v_asset from wnph.publication_source_assets a where a.source_package_id=v_batch.source_package_id and a.asset_key=v_asset_key and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id) order by a.created_at desc limit 1;
    if v_asset.id is null then raise exception 'WNPH bulk reconstruction: active asset % not found',v_asset_key; end if;
    v_page:=coalesce((v_asset.source_locator->>'sequence_index')::integer,0);
    select o.* into v_last_ws from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage' and o.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.ordinal desc limit 1;
    for v_ws in
      select o.* from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage' and o.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.ordinal,o.created_at
    loop
      select o.* into v_ia from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Internet Archive' and o.processor->>'engine'='DjVuXML OCR aligned window' and o.metadata->>'aligned_to_observation_id'=v_ws.id::text and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.created_at desc limit 1;
      v_reasons:='[]'::jsonb; v_risks:='[]'::jsonb;
      if v_ia.id is null then v_risks:=v_risks||'"missing_parallel_reading"'::jsonb; end if;
      if position('[ILLEGIBLE]' in upper(coalesce(v_ws.text_candidate,'')))>0 then v_risks:=v_risks||'"illegible_marker"'::jsonb; end if;
      if v_ws.text_candidate ~ '\{\{|\}\}' then v_risks:=v_risks||'"unresolved_transcription_markup"'::jsonb; end if;
      if v_is_first and coalesce(v_batch.stats->>'starts_inside_prior_semantic_unit','false')::boolean then v_risks:=v_risks||'"batch_starts_inside_prior_semantic_unit"'::jsonb; end if;
      if v_ws.id=v_last_ws.id and btrim(v_ws.text_candidate) !~ '[.!?][”’"'')\]]?$' then v_risks:=v_risks||'"cross_page_semantic_join_required"'::jsonb; end if;
      if v_ia.id is not null then v_sim:=extensions.similarity(wnph.normalize_parallel_reading_text_v1(v_ws.text_candidate),wnph.normalize_parallel_reading_text_v1(v_ia.text_candidate)); else v_sim:=0; end if;
      v_conf:=least(coalesce(v_ws.confidence,0),coalesce(v_ia.confidence,0),coalesce(v_sim,0));
      if v_sim<v_policy.min_parallel_similarity then v_risks:=v_risks||'"parallel_reading_disagreement"'::jsonb; end if;
      if v_conf<v_policy.min_proposal_confidence then v_risks:=v_risks||'"confidence_below_bulk_policy_floor"'::jsonb; end if;
      if jsonb_array_length(v_risks)>0 then v_reasons:=v_risks; end if;
      v_n:=v_n+1;
      v_item:=jsonb_build_object(
        'proposal_key',v_reconstruction_key||':'||lpad(v_n::text,5,'0'),
        'target_parent_block_id',v_batch.target_parent_block_id,
        'proposed_block_key',v_batch.batch_key||':paragraph:'||lpad(v_n::text,5,'0'),
        'proposed_ordinal',v_ord,'proposed_block_type','paragraph','proposed_semantic_role','historical_prose',
        'proposed_text_content',v_ws.text_candidate,'proposed_reading_state','usable',
        'source_observation_ids',case when v_ia.id is null then jsonb_build_array(v_ws.id) else jsonb_build_array(v_ws.id,v_ia.id) end,
        'confidence',v_conf,'disposition',case when jsonb_array_length(v_risks)=0 then 'auto_admit' else 'review' end,'review_reasons',v_reasons,
        'proposed_properties',jsonb_build_object(
          'bulk_batch_key',v_batch.batch_key,'bulk_risk_flags',v_risks,'bulk_parallel_similarity',v_sim,
          'bulk_primary_observation_id',v_ws.id,
          'bulk_consensus_observation_ids',case when v_ia.id is null then jsonb_build_array(v_ws.id) else jsonb_build_array(v_ws.id,v_ia.id) end,
          'source_surface_keys',jsonb_build_array(v_asset.asset_key),'scan_page',v_page
        ),
        'proposed_source_provenance',jsonb_build_object(
          'text_authority','parallel_reading_consensus_candidate_from_governed_source_observations',
          'derivation_method','wikisource_primary_candidate_aligned_against_contiguous_internet_archive_djvu_ocr_window_v1',
          'verification_status','machine_collated_not_forensically_verified','bulk_policy_key',v_policy.canonical_key,
          'source_locators',jsonb_build_array(jsonb_build_object('source_asset_id',v_asset.id,'source_asset_key',v_asset.asset_key,'sequence_index',v_page,'image_uri',v_asset.source_locator->>'image_uri'))
        ),
        'algorithm',jsonb_build_object('engine','wnph_bulk_parallel_reconstructor','version','1','auto_admit_rule','database-enforced bulk policy: aligned multi-processor evidence, normalized trigram similarity floor, confidence floor, zero unresolved risk flags; verified/adjudicated states are not produced')
      );
      v_proposals:=v_proposals||jsonb_build_array(v_item); v_ord:=v_ord+1; v_is_first:=false;
    end loop;
  end loop;
  if jsonb_array_length(v_proposals)=0 then raise exception 'WNPH bulk reconstruction: no Wikisource reading regions available'; end if;
  v_result:=public.wnph_commit_reconstruction_batch_v1((select canonical_key from wnph.publication_source_packages where id=v_batch.source_package_id),v_reconstruction_key,v_proposals,jsonb_build_object('bulk_batch_key',v_batch.batch_key,'bulk_policy_key',v_policy.canonical_key,'worker','wnph.run_bulk_parallel_reconstruction_v1','worker_version',1));
  update wnph.publication_source_bulk_batches set status=case when coalesce((v_result->>'promoted_blocks')::integer,0)>0 then 'qa_pending' else 'running' end,qa_status=case when coalesce((v_result->>'promoted_blocks')::integer,0)>0 then 'pending' else 'not_started' end,stats=stats||v_result where id=v_batch.id;
  if coalesce((v_result->>'promoted_blocks')::integer,0)>0 then perform wnph.seed_bulk_qa_samples_v1(v_batch.id); end if;
  return v_result;
end;
$$;

revoke execute on function wnph.harvest_parallel_reading_evidence_v1(text,text,text,integer,integer) from public,anon,authenticated;
revoke execute on function wnph.run_bulk_parallel_reconstruction_v1(uuid) from public,anon,authenticated;
revoke execute on function wnph.seed_bulk_qa_samples_v1(uuid) from public,anon,authenticated;