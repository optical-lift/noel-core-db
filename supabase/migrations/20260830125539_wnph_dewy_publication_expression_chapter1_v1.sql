do $block$
declare r record;
begin
  perform public.wnph_record_publication_expression_block_v2(
    'wish-fairy-dewy-dear:wnph-publication-e1','dewy:publication-expression:chapter1:v1','wnph:dewy:chapter:1',null,1,
    'chapter','chapter','CHAPTER I','admitted','structural_adjudication',0.99,
    'wnph_publication_expression_structural_adjudication_v2',array['dewy:chapter:1'],'[]'::jsonb,
    jsonb_build_object('publication_admission',true,'observed_title','Dewy Dear','printed_page_start',7,'printed_page_end',16,'publication_expression_only',true,'source_image_verification_required',false,'source_image_verification',false,'canonical_admission',false,'source_skeleton_unchanged',true),null
  );

  for r in
    select b.block_key,b.ordinal,b.text_content,b.reading_state,b.properties
    from wnph.publication_source_blocks b
    where b.block_key like 'dewy:chapter:1:paragraph:%'
      and not exists(select 1 from wnph.publication_source_blocks c where c.supersedes_block_id=b.id)
    order by b.ordinal
  loop
    if r.text_content is null or btrim(r.text_content)='' then
      raise exception 'WNPH Chapter I publication admission: source paragraph % has no text',r.block_key using errcode='55000';
    end if;
    perform public.wnph_record_publication_expression_block_v2(
      'wish-fairy-dewy-dear:wnph-publication-e1',
      format('dewy:publication-expression:chapter1:paragraph:%s:v1',lpad(r.ordinal::text,3,'0')),
      format('wnph:dewy:chapter:1:paragraph:%s',lpad(r.ordinal::text,3,'0')),
      'wnph:dewy:chapter:1',r.ordinal,'paragraph','body_paragraph',r.text_content,
      'admitted','editorial_reconstruction_high_confidence',0.99,
      'wnph_publication_expression_existing_governed_source_reading_v2',array[r.block_key],
      jsonb_build_array(jsonb_build_object('source_key','internet-archive:ia:wishfairydewydea00colv:djvu-text','evidence_role','same_surrogate_derivative','notes','Internet Archive DjVu OCR derivative of the same governed LOC/IA surrogate; used only as publication collation support and contributes zero additional historical-witness count.')),
      jsonb_build_object(
        'publication_admission',true,'publication_expression_only',true,
        'source_block_key',r.block_key,'source_block_reading_state',r.reading_state,
        'source_block_properties',coalesce(r.properties,'{}'::jsonb),
        'raw_ocr_sha256','7e9006f7f96af55c5ef4acb7f8572d6247c4573ce0bbc5cc8da6c2870be648fc',
        'same_surrogate_derivative',true,'historical_witness_count_delta',0,
        'source_image_verification_required',false,'source_image_verification',false,
        'canonical_admission',false,'source_forensic_stream_unchanged',true,
        'printed_page_range',jsonb_build_array(7,16)
      ),null
    );
  end loop;

  perform public.wnph_refresh_expression_manifestation_derivations_v1('wish-fairy-dewy-dear:wnph-publication-e1');
end;
$block$;