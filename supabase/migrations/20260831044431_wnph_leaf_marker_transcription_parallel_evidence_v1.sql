create or replace function wnph.join_transcription_physical_lines_v1(p_text text)
returns text
language plpgsql
immutable
set search_path=pg_catalog,wnph
as $$
declare v_line text; v_out text:='';
begin
  for v_line in select btrim(x) from regexp_split_to_table(replace(coalesce(p_text,''),E'\r',E''),E'\n') x loop
    if v_line='' then continue; end if;
    if v_out='' then v_out:=v_line;
    elsif right(v_out,1)='-' and v_line ~ '^[a-zſꝛ]' then v_out:=left(v_out,length(v_out)-1)||v_line;
    else v_out:=v_out||' '||v_line;
    end if;
  end loop;
  return btrim(regexp_replace(v_out,'[[:space:]]+',' ','g'));
end;
$$;

create or replace function wnph.harvest_leaf_marker_transcription_v1(
  p_source_package_key text,
  p_transcript_uri text,
  p_provider text,
  p_engine text,
  p_start_page integer,
  p_end_page integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,wnph,extensions
as $$
declare
  v_pkg_id uuid; v_resp extensions.http_response; v_text text; v_sections text[]; v_page integer; v_section text; v_asset wnph.publication_source_assets%rowtype;
  v_piece text; v_clean text; v_ord integer; v_key text; v_existing uuid; v_inserted integer:=0;
  v_ws wnph.publication_source_observations%rowtype; v_best_text text; v_best_conf numeric; v_best_ids uuid[]; v_best_sim numeric; v_align_inserted integer:=0;
begin
  select p.id into v_pkg_id from wnph.publication_source_packages p where p.canonical_key=p_source_package_key and not exists(select 1 from wnph.publication_source_packages c where c.supersedes_package_id=p.id) order by p.created_at desc limit 1;
  if v_pkg_id is null then raise exception 'WNPH leaf-marker harvest: active source package not found'; end if;
  v_resp:=wnph.http_get_with_retry_v1(p_transcript_uri,5,750);
  if v_resp.status<>200 then raise exception 'WNPH leaf-marker harvest: transcript returned %',v_resp.status; end if;
  v_text:=replace(v_resp.content,E'\r',E'');
  v_sections:=regexp_split_to_array(v_text,'\[[0-9]+[rv](?:[^]]*)\]');
  if coalesce(array_length(v_sections,1),0)-1<p_end_page then raise exception 'WNPH leaf-marker harvest: transcript exposes only % marked surfaces',coalesce(array_length(v_sections,1),0)-1; end if;
  for v_page in p_start_page..p_end_page loop
    v_section:=v_sections[v_page+1];
    select a.* into v_asset from wnph.publication_source_assets a where a.source_package_id=v_pkg_id and (a.source_locator->>'sequence_index')::integer=v_page and not exists(select 1 from wnph.publication_source_assets c where c.supersedes_asset_id=a.id) order by a.created_at desc limit 1;
    if v_asset.id is null then raise exception 'WNPH leaf-marker harvest: active source surface % missing',v_page; end if;
    v_ord:=0;
    for v_piece in select btrim(x) from regexp_split_to_table(coalesce(v_section,''),E'\n[ \t]*\n+') x where btrim(x)<>'' loop
      v_clean:=wnph.join_transcription_physical_lines_v1(v_piece);
      if v_clean='' then continue; end if;
      v_ord:=v_ord+1; v_key:=format('bulk:leaf-marker-transcript:%s:page:%s:region:%s:v1',substr(md5(p_transcript_uri),1,10),lpad(v_page::text,4,'0'),lpad(v_ord::text,3,'0'));
      select o.id into v_existing from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.observation_key=v_key and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) limit 1;
      if v_existing is null then
        insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
        values(v_asset.id,v_key,'region',v_ord,v_clean,'surface',.94,'leaf_marker_human_transcription_import_with_physical_line_join','plain_text_leaf_marker_transcript',
          jsonb_build_object('provider',p_provider,'engine',p_engine,'version','source-declared'),jsonb_build_object('transcript_uri',p_transcript_uri,'scan_page',v_page),
          jsonb_build_object('canonical_authority',false,'bulk_evidence',true,'reading_family','leaf_marker_human_transcription','promotion_allowed',false));
        v_inserted:=v_inserted+1;
      end if;
    end loop;

    for v_ws in select o.* from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.processor->>'provider'='Wikisource' and o.processor->>'engine'='ProofreadPage' and o.metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) order by o.ordinal loop
      select q.window_text,q.window_conf,q.obs_ids,q.sim into v_best_text,v_best_conf,v_best_ids,v_best_sim
      from (
        select string_agg(o.text_candidate,' ' order by o.ordinal) window_text,min(o.confidence) window_conf,array_agg(o.id order by o.ordinal) obs_ids,
               extensions.similarity(wnph.normalize_parallel_reading_text_v1(v_ws.text_candidate),wnph.normalize_parallel_reading_text_v1(string_agg(o.text_candidate,' ' order by o.ordinal))) sim,
               s.start_ord,k.len
        from (select distinct ordinal start_ord from wnph.publication_source_observations where source_asset_id=v_asset.id and processor->>'provider'=p_provider and processor->>'engine'=p_engine and metadata->>'bulk_evidence'='true' and not exists(select 1 from wnph.publication_source_observations cc where cc.supersedes_observation_id=publication_source_observations.id)) s
        cross join generate_series(1,6) k(len)
        join wnph.publication_source_observations o on o.source_asset_id=v_asset.id and o.processor->>'provider'=p_provider and o.processor->>'engine'=p_engine and o.metadata->>'bulk_evidence'='true' and o.ordinal between s.start_ord and s.start_ord+k.len-1 and not exists(select 1 from wnph.publication_source_observations cc where cc.supersedes_observation_id=o.id)
        group by s.start_ord,k.len having count(*)=k.len
      ) q order by q.sim desc,abs(q.start_ord-coalesce(v_ws.ordinal,1)),q.len asc limit 1;
      if v_best_text is null then continue; end if;
      v_key:=format('bulk:leaf-marker-aligned:%s:page:%s:region:%s:v1',substr(md5(p_transcript_uri),1,10),lpad(v_page::text,4,'0'),lpad(coalesce(v_ws.ordinal,0)::text,3,'0'));
      select o.id into v_existing from wnph.publication_source_observations o where o.source_asset_id=v_asset.id and o.observation_key=v_key and not exists(select 1 from wnph.publication_source_observations c where c.supersedes_observation_id=o.id) limit 1;
      if v_existing is null then
        insert into wnph.publication_source_observations(source_asset_id,observation_key,observation_kind,ordinal,text_candidate,coordinate_unit,confidence,derivation_method,source_format,processor,external_locator,metadata)
        values(v_asset.id,v_key,'region',v_ws.ordinal,v_best_text,'surface',v_best_conf,'contiguous_leaf_marker_transcript_region_window_alignment_by_normalized_trigram_v1','aligned_leaf_marker_transcript_window',
          jsonb_build_object('provider',p_provider,'engine',p_engine||' aligned window','version','1'),jsonb_build_object('transcript_uri',p_transcript_uri,'scan_page',v_page,'aligned_to_observation_id',v_ws.id),
          jsonb_build_object('canonical_authority',false,'bulk_evidence',true,'reading_family','leaf_marker_human_transcription_aligned','promotion_allowed',false,'aligned_to_observation_id',v_ws.id,'source_observation_ids',to_jsonb(v_best_ids),'alignment_similarity',v_best_sim));
        v_align_inserted:=v_align_inserted+1;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('source_package_key',p_source_package_key,'page_start',p_start_page,'page_end',p_end_page,'transcript_regions_inserted',v_inserted,'aligned_regions_inserted',v_align_inserted,'provider',p_provider,'engine',p_engine);
end;
$$;

revoke execute on function wnph.harvest_leaf_marker_transcription_v1(text,text,text,text,integer,integer) from public,anon,authenticated;