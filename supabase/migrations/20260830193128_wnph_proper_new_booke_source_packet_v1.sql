do $$
declare
  v_pkg uuid;
  v_surrogate uuid;
  v_source uuid;
  v_root uuid;
  v_front uuid;
  v_title_stream uuid;
  i integer;
  v_uri text;
begin
  select p.id into strict v_pkg from wnph.publication_source_packages p where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1' and not exists(select 1 from wnph.publication_source_packages n where n.supersedes_package_id=p.id);
  select s.id into strict v_surrogate from wnph.surrogates s where s.canonical_key='proper-new-booke-of-cookery:commons-ia-1575';
  select es.id into strict v_source from wnph.evidence_sources es where es.canonical_key='wikimedia-commons:proper-new-booke-cookery-1575';

  insert into wnph.publication_source_blocks(source_package_id,block_key,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_pkg,'proper-new-booke:document',0,'document','book_root',jsonb_build_object('witness_year',1575),jsonb_build_object('structure_authority','wnph_recovery_plan')) returning id into v_root;

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_pkg,'proper-new-booke:front-matter',v_root,1,'section','front_matter',jsonb_build_object('witness_year',1575),jsonb_build_object('structure_authority','source_page_sequence')) returning id into v_front;

  insert into wnph.publication_source_blocks(source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance)
  values(v_pkg,'proper-new-booke:title-page:reading-stream',v_front,1,'reading_stream','title_page',jsonb_build_object('scan_page',1,'completion',false),jsonb_build_object('structure_authority','governed_1575_source_surface')) returning id into v_title_stream;

  for i in 1..33 loop
    v_uri := 'https://upload.wikimedia.org/wikipedia/commons/thumb/c/cd/A_Proper_New_Booke_of_Cookery_%281575%29.djvu/page' || i::text || '-934px-A_Proper_New_Booke_of_Cookery_%281575%29.djvu.jpg';
    insert into wnph.publication_source_assets(source_package_id,asset_key,asset_role,source_surrogate_id,evidence_source_id,source_locator,storage_uri,media_type,metadata)
    values(v_pkg,'proper-new-booke:1575:source-surface:'||lpad(i::text,4,'0'),'source_surface',v_surrogate,v_source,
      jsonb_build_object('sequence_index',i,'scan_page',i,'image_uri',v_uri,'commons_file','A Proper New Booke of Cookery (1575).djvu','wikisource_page','https://en.wikisource.org/wiki/Page:A_Proper_New_Booke_of_Cookery_(1575).djvu/'||i::text),
      v_uri,'image/jpeg',jsonb_build_object('surface_kind','page_render','render_width_px',934,'master_mime_type','image/vnd.djvu','master_page_count',33,'page_sequence_status','repository_ordered'));
  end loop;

  if (select count(*) from wnph.publication_source_assets a where a.source_package_id=v_pkg and a.asset_role='source_surface' and not exists(select 1 from wnph.publication_source_assets n where n.supersedes_asset_id=a.id))<>33 then
    raise exception 'expected 33 source surfaces';
  end if;
end $$;