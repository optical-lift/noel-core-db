
create or replace function instrument.materialize_unknown_canon_frames_v1(
  p_run_key text,
  p_book text default 'Gen',
  p_witness text default 'mt_noel_current',
  p_sizes integer[] default array[4,8,16]
)
returns jsonb
language plpgsql
as $function$
declare
  v_run_id bigint;
  v_status text;
  v_object_count bigint;
begin
  if p_sizes is null or cardinality(p_sizes)=0 then
    raise exception 'At least one frame size is required';
  end if;
  if exists(select 1 from unnest(p_sizes) x where x < 2 or x > 64) then
    raise exception 'Frame sizes must be between 2 and 64';
  end if;

  select instrument_run_id,run_status into v_run_id,v_status
  from instrument.runs where run_key=p_run_key;

  if v_run_id is null then
    insert into instrument.runs(
      run_key,run_kind,blindness_class,maximum_prior_load_level,engine_key,
      corpus_scope,boundary_mode,prohibited_feature_families,methodology_version,
      input_snapshot,run_status
    )
    values(
      p_run_key,'discovery','strict_blind',2,'unknown_structure_multiscale_v1',
      jsonb_build_object(
        'source_family','canon',
        'projection','forward_frames',
        'witness_key',p_witness,
        'canonical_book',p_book,
        'frame_sizes',to_jsonb(p_sizes),
        'semantic_decode','prohibited_until_frozen_rejoin'
      ),
      'canonical_boundaries',
      '["english_gloss","strong_route","song_function","song_object","prior_pattern","blind_target_benchmark"]'::jsonb,
      'noel_unknown_structure_v1',
      '{}'::jsonb,
      'planned'
    )
    returning instrument_run_id into v_run_id;
  else
    if v_status<>'planned' then
      raise exception 'Run % already has immutable status %; create a new run key',p_run_key,v_status;
    end if;
    delete from instrument.unknown_structure_objects where run_id=v_run_id;
  end if;

  with tok0 as (
    select
      a.witness_key,a.canonical_book_code,a.chapter,a.verse,a.token_position,
      a.source_token_id,a.token_class,a.anonymous_lemma_hash,
      row_number() over(
        partition by a.witness_key,a.canonical_book_code,a.chapter
        order by a.verse,a.token_position,a.source_token_id
      )::int as chapter_pos,
      count(*) over(
        partition by a.witness_key,a.canonical_book_code,a.chapter
      )::int as chapter_n
    from instrument.anonymous_token_identity_l2 a
    where a.witness_key=p_witness
      and a.canonical_book_code=p_book
      and a.anonymous_lemma_hash is not null
  ),
  exp0 as (
    select
      c.witness_key,c.canonical_book_code,c.chapter,c.verse as start_verse,
      c.token_position as start_token_position,c.source_token_id as start_source_token_id,
      c.chapter_pos as start_chapter_pos,s.frame_size,
      w.chapter_pos,w.verse,w.token_position,w.token_class,w.anonymous_lemma_hash as win_hash,
      min(w.chapter_pos) over(
        partition by c.chapter,c.chapter_pos,s.frame_size,w.anonymous_lemma_hash
      ) as first_pos
    from tok0 c
    cross join lateral unnest(p_sizes) s(frame_size)
    join tok0 w
      on w.witness_key=c.witness_key
     and w.canonical_book_code=c.canonical_book_code
     and w.chapter=c.chapter
     and w.chapter_pos between c.chapter_pos and c.chapter_pos+s.frame_size-1
    where c.chapter_pos+s.frame_size-1<=c.chapter_n
  ),
  exp1 as (
    select e.*,
      dense_rank() over(
        partition by chapter,start_chapter_pos,frame_size
        order by first_pos,win_hash
      )::int as eq_id
    from exp0 e
  ),
  ag as (
    select
      witness_key,canonical_book_code,chapter,start_verse,start_token_position,
      start_source_token_id,start_chapter_pos,frame_size,
      count(*)::int as token_count,
      count(distinct win_hash)::int as distinct_identity_count,
      string_agg(eq_id::text,'.' order by chapter_pos) as equality_skeleton,
      string_agg(coalesce(token_class,'?'),'.' order by chapter_pos) as class_skeleton,
      md5(string_agg(win_hash,'|' order by chapter_pos)) as exact_sequence_hash,
      max(verse)::int as end_verse
    from exp1
    group by witness_key,canonical_book_code,chapter,start_verse,start_token_position,
             start_source_token_id,start_chapter_pos,frame_size
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,witness_key,canonical_book_code,chapter,verse,center_position,
    scale_key,source_ref,anonymous_payload,record_status
  )
  select
    v_run_id,
    'USO_CANON_FRAME_'||upper(substr(md5(v_run_id::text||':'||chapter::text||':'||
      start_chapter_pos::text||':'||frame_size::text),1,20)),
    'canon','token_frame','ordered_equality_sequence',
    md5('ordered_equality_sequence|'||frame_size::text||'|'||equality_skeleton),
    md5('canon_frame|'||frame_size::text||'|'||equality_skeleton||'|'||class_skeleton),
    witness_key,canonical_book_code,chapter,start_verse,start_token_position,
    'frame_n'||frame_size::text,
    jsonb_build_object(
      'witness_key',witness_key,'canonical_book_code',canonical_book_code,
      'chapter',chapter,'start_verse',start_verse,'end_verse',end_verse,
      'start_token_position',start_token_position,'source_token_id',start_source_token_id
    ),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'sequence_length',frame_size,
      'distinct_identity_count',distinct_identity_count,
      'equality_skeleton',equality_skeleton,
      'class_skeleton',class_skeleton,
      'exact_sequence_hash',exact_sequence_hash
    ),
    'measured'
  from ag;

  get diagnostics v_object_count=row_count;

  update instrument.runs
    set input_snapshot=jsonb_build_object(
      'materialized_object_count',v_object_count,
      'object_signature_hash',(
        select md5(string_agg(object_key||':'||anonymous_signature,'|' order by object_key))
        from instrument.unknown_structure_objects where run_id=v_run_id
      )
    ),
    run_status='complete',
    updated_at=now()
  where instrument_run_id=v_run_id;

  return jsonb_build_object(
    'run_id',v_run_id,'run_key',p_run_key,'source_family','canon',
    'projection','forward_frames','book',p_book,'witness',p_witness,
    'frame_sizes',to_jsonb(p_sizes),'objects',v_object_count,'semantic_decode','not_opened'
  );
end
$function$;
