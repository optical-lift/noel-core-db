
create or replace function instrument.materialize_unknown_canon_multiscale_v1(
  p_run_key text,
  p_book text default 'Gen',
  p_witness text default 'mt_noel_current',
  p_radii integer[] default array[1,3,7,15]
)
returns jsonb
language plpgsql
as $function$
declare
  v_run_id bigint;
  v_status text;
  v_object_count bigint;
  v_feature_count bigint;
begin
  if p_radii is null or cardinality(p_radii)=0 then
    raise exception 'At least one radius is required';
  end if;
  if exists(select 1 from unnest(p_radii) x where x < 1 or x > 64) then
    raise exception 'Radii must be between 1 and 64';
  end if;

  select instrument_run_id,run_status
    into v_run_id,v_status
  from instrument.runs
  where run_key=p_run_key;

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
        'witness_key',p_witness,
        'canonical_book',p_book,
        'radii',to_jsonb(p_radii),
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
    if not exists(
      select 1 from instrument.runs
      where instrument_run_id=v_run_id
        and engine_key='unknown_structure_multiscale_v1'
        and blindness_class='strict_blind'
        and maximum_prior_load_level<=2
        and corpus_scope->>'source_family'='canon'
        and corpus_scope->>'witness_key'=p_witness
        and corpus_scope->>'canonical_book'=p_book
    ) then
      raise exception 'Run % does not satisfy strict-blind unknown-structure contract',p_run_key;
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
      row_number() over(
        partition by a.witness_key,a.canonical_book_code
        order by a.chapter,a.verse,a.token_position,a.source_token_id
      )::int as book_pos,
      count(*) over(
        partition by a.witness_key,a.canonical_book_code
      )::int as book_n,
      count(*) over(
        partition by a.witness_key,a.canonical_book_code,a.anonymous_lemma_hash
      )::int as center_identity_frequency
    from instrument.anonymous_token_identity_l2 a
    where a.witness_key=p_witness
      and a.canonical_book_code=p_book
      and a.anonymous_lemma_hash is not null
  ),
  expanded0 as (
    select
      c.witness_key,c.canonical_book_code,c.chapter,
      c.verse as center_verse,c.token_position as center_token_position,
      c.source_token_id as center_source_token_id,
      c.book_pos as center_book_pos,c.chapter_pos as center_chapter_pos,
      c.anonymous_lemma_hash as center_hash,
      c.center_identity_frequency,c.book_n,
      r.radius,
      w.verse as win_verse,w.chapter_pos as win_chapter_pos,
      w.token_class,w.anonymous_lemma_hash as win_hash,
      lag(w.anonymous_lemma_hash) over(
        partition by c.book_pos,r.radius
        order by w.chapter_pos
      ) as prev_hash,
      min(w.chapter_pos) over(
        partition by c.book_pos,r.radius,w.anonymous_lemma_hash
      ) as first_pos,
      count(*) over(
        partition by c.book_pos,r.radius
      )::numeric as window_n,
      count(*) over(
        partition by c.book_pos,r.radius,w.anonymous_lemma_hash
      )::numeric as identity_n
    from tok0 c
    cross join lateral unnest(p_radii) r(radius)
    join tok0 w
      on w.witness_key=c.witness_key
     and w.canonical_book_code=c.canonical_book_code
     and w.chapter=c.chapter
     and w.chapter_pos between c.chapter_pos-r.radius and c.chapter_pos+r.radius
  ),
  expanded1 as (
    select e.*,
      dense_rank() over(
        partition by center_book_pos,radius
        order by first_pos,win_hash
      )::int as eq_id
    from expanded0 e
  ),
  ag as (
    select
      witness_key,canonical_book_code,chapter,center_verse,center_token_position,
      center_source_token_id,center_book_pos,center_chapter_pos,center_hash,
      center_identity_frequency,book_n,radius,
      count(*)::int as token_count,
      count(distinct win_hash)::int as distinct_identity_count,
      (count(*)-count(distinct win_hash))::int as repeat_count,
      count(distinct win_verse)::int as span_verse_count,
      count(distinct win_hash) filter(where win_chapter_pos<center_chapter_pos)::int as left_distinct_count,
      count(distinct win_hash) filter(where win_chapter_pos>center_chapter_pos)::int as right_distinct_count,
      count(*) filter(where win_hash=prev_hash)::int as adjacent_repeat_count,
      sum(-(1.0/window_n) * ln(identity_n/window_n))::numeric as identity_entropy,
      string_agg(eq_id::text,'.' order by win_chapter_pos) as equality_skeleton,
      string_agg(coalesce(token_class,'?'),'.' order by win_chapter_pos) as class_skeleton,
      md5(string_agg(win_hash,'|' order by win_chapter_pos)) as exact_signature
    from expanded1
    group by
      witness_key,canonical_book_code,chapter,center_verse,center_token_position,
      center_source_token_id,center_book_pos,center_chapter_pos,center_hash,
      center_identity_frequency,book_n,radius
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,witness_key,canonical_book_code,chapter,verse,center_position,
    scale_key,source_ref,anonymous_payload,record_status
  )
  select
    v_run_id,
    'USO_CANON_'||upper(substr(md5(v_run_id::text||':'||canonical_book_code||':'||center_book_pos::text||':'||radius::text),1,20)),
    'canon','token_window','ordered_equality_sequence',
    md5('ordered_equality_sequence|'||token_count::text||'|'||equality_skeleton),
    md5('canon_window|'||radius::text||'|'||equality_skeleton||'|'||class_skeleton),
    witness_key,canonical_book_code,chapter,center_verse,center_token_position,
    'tok_r'||radius::text,
    jsonb_build_object(
      'witness_key',witness_key,
      'canonical_book_code',canonical_book_code,
      'chapter',chapter,
      'verse',center_verse,
      'token_position',center_token_position,
      'source_token_id',center_source_token_id
    ),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'center_anonymous_hash',center_hash,
      'exact_sequence_hash',exact_signature,
      'equality_skeleton',equality_skeleton,
      'class_skeleton',class_skeleton,
      'metrics',jsonb_build_object(
        'window_token_count',token_count,
        'window_distinct_identity_count',distinct_identity_count,
        'window_repeat_count',repeat_count,
        'window_identity_entropy',identity_entropy,
        'window_span_verse_count',span_verse_count,
        'window_left_distinct_count',left_distinct_count,
        'window_right_distinct_count',right_distinct_count,
        'window_adjacent_repeat_count',adjacent_repeat_count,
        'center_identity_frequency',center_identity_frequency,
        'center_identity_surprisal',(-ln(center_identity_frequency::numeric/book_n::numeric))
      )
    ),
    'measured'
  from ag;

  get diagnostics v_object_count=row_count;

  insert into instrument.unknown_structure_features(
    unknown_object_id,feature_key,value_kind,integer_value,feature_origin,strict_blind_allowed
  )
  select o.unknown_object_id,x.feature_key,'integer',x.val,'derived',true
  from instrument.unknown_structure_objects o
  cross join lateral (
    values
      ('usd_window_token_count',(o.anonymous_payload#>>'{metrics,window_token_count}')::bigint),
      ('usd_window_distinct_identity_count',(o.anonymous_payload#>>'{metrics,window_distinct_identity_count}')::bigint),
      ('usd_window_adjacent_repeat_count',(o.anonymous_payload#>>'{metrics,window_adjacent_repeat_count}')::bigint),
      ('usd_window_left_distinct_count',(o.anonymous_payload#>>'{metrics,window_left_distinct_count}')::bigint),
      ('usd_window_right_distinct_count',(o.anonymous_payload#>>'{metrics,window_right_distinct_count}')::bigint),
      ('usd_window_span_verse_count',(o.anonymous_payload#>>'{metrics,window_span_verse_count}')::bigint),
      ('usd_center_identity_frequency',(o.anonymous_payload#>>'{metrics,center_identity_frequency}')::bigint)
  ) x(feature_key,val)
  where o.run_id=v_run_id;

  insert into instrument.unknown_structure_features(
    unknown_object_id,feature_key,value_kind,numeric_value,feature_origin,strict_blind_allowed
  )
  select o.unknown_object_id,x.feature_key,'numeric',x.val,'derived',true
  from instrument.unknown_structure_objects o
  cross join lateral (
    values
      ('usd_window_identity_entropy',(o.anonymous_payload#>>'{metrics,window_identity_entropy}')::numeric),
      ('usd_center_identity_surprisal',(o.anonymous_payload#>>'{metrics,center_identity_surprisal}')::numeric)
  ) x(feature_key,val)
  where o.run_id=v_run_id;

  insert into instrument.unknown_structure_features(
    unknown_object_id,feature_key,value_kind,categorical_value,feature_origin,strict_blind_allowed
  )
  select o.unknown_object_id,'usd_sequence_equality_skeleton','categorical',
         o.anonymous_payload->>'equality_skeleton','topological',true
  from instrument.unknown_structure_objects o where o.run_id=v_run_id
  union all
  select o.unknown_object_id,'usd_sequence_class_skeleton','categorical',
         o.anonymous_payload->>'class_skeleton','topological',true
  from instrument.unknown_structure_objects o where o.run_id=v_run_id;

  select count(*) into v_feature_count
  from instrument.unknown_structure_features f
  join instrument.unknown_structure_objects o using(unknown_object_id)
  where o.run_id=v_run_id;

  update instrument.runs
    set input_snapshot=jsonb_build_object(
          'materialized_object_count',v_object_count,
          'materialized_feature_count',v_feature_count,
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
    'book',p_book,'witness',p_witness,'radii',to_jsonb(p_radii),
    'objects',v_object_count,'features',v_feature_count,'semantic_decode','not_opened'
  );
end
$function$;

create or replace function instrument.materialize_unknown_mark_multiscale_v1(
  p_run_key text
)
returns jsonb
language plpgsql
as $function$
declare
  v_run_id bigint;
  v_status text;
  v_object_count bigint;
begin
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
        'source_family','mark',
        'source_relations',jsonb_build_array(
          'mark.regions','mark.instances','mark.components','mark.component_relations',
          'mark.sequence_zones','mark.sequence_members','mark.blind_feature_observations_v1'
        ),
        'semantic_decode','prohibited_until_frozen_rejoin'
      ),
      'source_boundaries',
      '["song_function","song_object","prior_pattern","blind_target_benchmark"]'::jsonb,
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

  with base as (
    select r.region_id,r.region_key,r.capture_id,r.parent_region_id,
           r.bbox_width,r.bbox_height,
           (r.bbox_width::numeric*r.bbox_height::numeric) as area,
           case when r.bbox_height=0 then null else r.bbox_width::numeric/r.bbox_height::numeric end as aspect,
           count(distinct c.component_id)::int as component_count,
           count(distinct cr.component_relation_id)::int as relation_count,
           count(distinct child.region_id)::int as child_region_count
    from mark.regions r
    left join mark.components c on c.region_id=r.region_id
    left join mark.component_relations cr on cr.evidence_region_id=r.region_id
    left join mark.regions child on child.parent_region_id=r.region_id
    group by r.region_id,r.region_key,r.capture_id,r.parent_region_id,r.bbox_width,r.bbox_height
  ),
  binned as (
    select b.*,
      ntile(8) over(order by area,region_id) as area_bin,
      ntile(8) over(order by aspect nulls last,region_id) as aspect_bin
    from base b
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,scale_key,source_ref,anonymous_payload
  )
  select
    v_run_id,
    'USO_MARK_REGION_'||upper(substr(md5(v_run_id::text||':'||region_id::text),1,18)),
    'mark','region','bounded_region_profile',
    md5('bounded_region_profile|'||area_bin||'|'||aspect_bin||'|'||
        least(component_count,8)||'|'||least(relation_count,8)||'|'||least(child_region_count,8)),
    md5('mark_region|'||area_bin||'|'||aspect_bin||'|'||
        least(component_count,8)||'|'||least(relation_count,8)||'|'||least(child_region_count,8)),
    'region',
    jsonb_build_object('region_id',region_id,'capture_id',capture_id),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'geometry',jsonb_build_object(
        'width',bbox_width,'height',bbox_height,'area',area,'aspect',aspect,
        'area_bin',area_bin,'aspect_bin',aspect_bin
      ),
      'topology',jsonb_build_object(
        'component_count',component_count,'relation_count',relation_count,
        'child_region_count',child_region_count
      )
    )
  from binned;

  with base as (
    select cr.component_relation_id,cr.subject_component_id,cr.object_component_id,
           cr.evidence_region_id,cr.distance_px,cr.angle_degrees,
           sc.component_order as subject_order,oc.component_order as object_order
    from mark.component_relations cr
    join mark.components sc on sc.component_id=cr.subject_component_id
    join mark.components oc on oc.component_id=cr.object_component_id
  ),
  binned as (
    select b.*,
      ntile(8) over(order by distance_px nulls last,component_relation_id) as distance_bin,
      ntile(12) over(order by angle_degrees nulls last,component_relation_id) as angle_bin,
      case when subject_order is null or object_order is null then 'U'
           when subject_order<object_order then 'F'
           when subject_order>object_order then 'B'
           else 'S' end as order_relation
    from base b
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,scale_key,source_ref,anonymous_payload
  )
  select
    v_run_id,
    'USO_MARK_REL_'||upper(substr(md5(v_run_id::text||':'||component_relation_id::text),1,18)),
    'mark','component_relation','pair_relation_profile',
    md5('pair_relation_profile|'||distance_bin||'|'||angle_bin||'|'||order_relation),
    md5('mark_relation|'||distance_bin||'|'||angle_bin||'|'||order_relation),
    'relation',
    jsonb_build_object(
      'component_relation_id',component_relation_id,
      'subject_component_id',subject_component_id,
      'object_component_id',object_component_id,
      'evidence_region_id',evidence_region_id
    ),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'distance_bin',distance_bin,'angle_bin',angle_bin,'order_relation',order_relation,
      'distance_px',distance_px,'angle_degrees',angle_degrees
    )
  from binned;

  with obs as (
    select
      c.component_id,c.component_key,c.instance_id,c.region_id,c.component_order,
      md5(c.channel_key) as anonymous_channel_hash,
      coalesce(
        string_agg(
          md5(b.feature_key)||':'||
          coalesce(
            case when b.boolean_value is not null then 'b='||b.boolean_value::text end,
            case when b.integer_value is not null then 'i='||b.integer_value::text end,
            case when b.numeric_value is not null then 'n='||round(b.numeric_value,4)::text end,
            case when b.categorical_value is not null then 'c='||md5(b.categorical_value) end,
            'x'
          ),
          '|' order by md5(b.feature_key)
        ),
        'NO_FEATURE'
      ) as blind_feature_fingerprint
    from mark.components c
    left join mark.blind_feature_observations_v1 b on b.component_id=c.component_id
    group by c.component_id,c.component_key,c.instance_id,c.region_id,c.component_order,c.channel_key
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,scale_key,source_ref,anonymous_payload
  )
  select
    v_run_id,
    'USO_MARK_COMP_'||upper(substr(md5(v_run_id::text||':'||component_id::text),1,18)),
    'mark','component','component_profile',
    md5('component_profile|'||anonymous_channel_hash||'|'||blind_feature_fingerprint),
    md5('mark_component|'||anonymous_channel_hash||'|'||blind_feature_fingerprint),
    'component',
    jsonb_build_object('component_id',component_id,'instance_id',instance_id,'region_id',region_id),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'anonymous_channel_hash',anonymous_channel_hash,
      'blind_feature_fingerprint',md5(blind_feature_fingerprint),
      'component_order',component_order
    )
  from obs;

  with instance_fp as (
    select
      i.instance_id,
      md5(coalesce(string_agg(md5(c.channel_key),'|' order by c.component_order nulls last,c.component_id),'EMPTY')) as fp
    from mark.instances i
    left join mark.components c on c.instance_id=i.instance_id
    group by i.instance_id
  ),
  seq0 as (
    select
      z.sequence_zone_id,z.zone_key,z.region_id,
      sm.ordinal_position,sm.instance_id,fp.fp,
      min(sm.ordinal_position) over(partition by z.sequence_zone_id,fp.fp) as first_pos
    from mark.sequence_zones z
    join mark.sequence_members sm on sm.sequence_zone_id=z.sequence_zone_id
    join instance_fp fp on fp.instance_id=sm.instance_id
  ),
  seq1 as (
    select s.*,
      dense_rank() over(
        partition by sequence_zone_id
        order by first_pos,fp
      )::int as eq_id
    from seq0 s
  ),
  ag as (
    select
      sequence_zone_id,zone_key,region_id,
      count(*)::int as sequence_length,
      count(distinct fp)::int as distinct_identity_count,
      string_agg(eq_id::text,'.' order by ordinal_position) as equality_skeleton,
      md5(string_agg(fp,'|' order by ordinal_position)) as exact_signature
    from seq1
    group by sequence_zone_id,zone_key,region_id
  )
  insert into instrument.unknown_structure_objects(
    run_id,object_key,source_family,object_kind,topology_family,topology_signature,
    anonymous_signature,scale_key,source_ref,anonymous_payload
  )
  select
    v_run_id,
    'USO_MARK_SEQ_'||upper(substr(md5(v_run_id::text||':'||sequence_zone_id::text),1,18)),
    'mark','sequence_zone','ordered_equality_sequence',
    md5('ordered_equality_sequence|'||sequence_length::text||'|'||equality_skeleton),
    md5('mark_sequence|'||equality_skeleton||'|'||exact_signature),
    'sequence_zone',
    jsonb_build_object('sequence_zone_id',sequence_zone_id,'region_id',region_id),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'sequence_length',sequence_length,
      'distinct_identity_count',distinct_identity_count,
      'equality_skeleton',equality_skeleton,
      'exact_sequence_hash',exact_signature
    )
  from ag;

  select count(*) into v_object_count
  from instrument.unknown_structure_objects
  where run_id=v_run_id;

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
    'run_id',v_run_id,'run_key',p_run_key,'source_family','mark',
    'objects',v_object_count,'semantic_decode','not_opened'
  );
end
$function$;

create or replace function instrument.discover_unknown_topologies_v1(
  p_run_key text,
  p_min_occurrences integer default 4,
  p_min_distinct_units integer default 3
)
returns jsonb
language plpgsql
as $function$
declare
  v_run_id bigint;
  v_status text;
  v_candidate_count bigint;
  v_member_count bigint;
  v_set_key text;
  v_snapshot_hash text;
begin
  select instrument_run_id,run_status into v_run_id,v_status
  from instrument.runs
  where run_key=p_run_key
    and engine_key='unknown_structure_multiscale_v1'
    and blindness_class='strict_blind'
    and maximum_prior_load_level<=2;

  if v_run_id is null then
    raise exception 'Unknown strict-blind unknown-structure run %',p_run_key;
  end if;
  if v_status<>'complete' then
    raise exception 'Run % must be complete before discovery; status=%',p_run_key,v_status;
  end if;
  if p_min_occurrences<2 or p_min_distinct_units<1 then
    raise exception 'Invalid discovery thresholds';
  end if;

  with grouped as (
    select
      scale_key,topology_family,anonymous_signature,topology_signature,
      count(*)::int as occurrence_count,
      count(distinct case
        when source_family='canon' then coalesce(canonical_book_code,'?')||':'||coalesce(chapter::text,'?')
        else coalesce((source_ref->>'region_id'),(source_ref->>'evidence_region_id'),object_key)
      end)::int as distinct_unit_count,
      min(source_family) as source_family
    from instrument.unknown_structure_objects
    where run_id=v_run_id
    group by scale_key,topology_family,anonymous_signature,topology_signature
    having count(*)>=p_min_occurrences
       and count(distinct case
        when source_family='canon' then coalesce(canonical_book_code,'?')||':'||coalesce(chapter::text,'?')
        else coalesce((source_ref->>'region_id'),(source_ref->>'evidence_region_id'),object_key)
      end)>=p_min_distinct_units
  )
  insert into instrument.structure_candidates(
    candidate_key,discovery_run_id,engine_key,anonymous_label,
    neutral_structure,discovery_support,candidate_status
  )
  select
    'USC_'||upper(substr(md5(v_run_id::text||':'||scale_key||':'||anonymous_signature),1,14)),
    v_run_id,'unknown_structure_multiscale_v1',
    'USC_'||upper(substr(md5(scale_key||':'||anonymous_signature),1,10)),
    jsonb_build_object(
      'structure_kind','anonymous_multiscale_topology',
      'source_family',source_family,
      'scale_key',scale_key,
      'topology_family',topology_family,
      'anonymous_signature',anonymous_signature,
      'topology_signature',topology_signature,
      'semantic_decode','not_opened'
    ),
    jsonb_build_object(
      'occurrence_count',occurrence_count,
      'distinct_unit_count',distinct_unit_count,
      'minimum_occurrences',p_min_occurrences,
      'minimum_distinct_units',p_min_distinct_units,
      'discovery_phase','strict_blind_pre_rejoin'
    ),
    'candidate'
  from grouped;

  get diagnostics v_candidate_count=row_count;

  insert into instrument.unknown_structure_candidate_members(
    structure_candidate_id,unknown_object_id,member_ordinal,member_role,member_payload
  )
  select
    c.structure_candidate_id,o.unknown_object_id,
    row_number() over(
      partition by c.structure_candidate_id
      order by o.canonical_book_code nulls last,o.chapter nulls last,o.verse nulls last,
               o.center_position nulls last,o.unknown_object_id
    )::int,
    'support',
    jsonb_build_object(
      'source_family',o.source_family,
      'scale_key',o.scale_key,
      'semantic_decode','not_opened'
    )
  from instrument.structure_candidates c
  join instrument.unknown_structure_objects o
    on o.run_id=c.discovery_run_id
   and o.scale_key=c.neutral_structure->>'scale_key'
   and o.anonymous_signature=c.neutral_structure->>'anonymous_signature'
  where c.discovery_run_id=v_run_id;

  get diagnostics v_member_count=row_count;

  v_set_key := 'USC_SET_'||upper(substr(md5(p_run_key||':blind_topology_set_v1'),1,14));

  insert into instrument.structure_candidate_sets(
    candidate_set_key,method_key,source_run_id,set_purpose,expected_candidate_count,
    set_status,frozen_at,metadata
  )
  values(
    v_set_key,null,v_run_id,'strict_blind_unknown_structure_topology',
    v_candidate_count,'frozen',now(),
    jsonb_build_object(
      'semantic_decode','not_opened',
      'min_occurrences',p_min_occurrences,
      'min_distinct_units',p_min_distinct_units,
      'freeze_rule','candidates and membership frozen before source-coordinate or Song rejoin'
    )
  );

  insert into instrument.structure_candidate_set_members(
    candidate_set_key,structure_candidate_id,member_ordinal
  )
  select
    v_set_key,c.structure_candidate_id,
    row_number() over(order by c.candidate_key)::int
  from instrument.structure_candidates c
  where c.discovery_run_id=v_run_id
  order by c.candidate_key;

  v_snapshot_hash := md5(
    coalesce((
      select string_agg(
        c.candidate_key||':'||
        coalesce(c.discovery_support->>'occurrence_count','0')||':'||
        coalesce(c.discovery_support->>'distinct_unit_count','0'),
        '|' order by c.candidate_key
      )
      from instrument.structure_candidates c
      where c.discovery_run_id=v_run_id
    ),'EMPTY')
  );

  insert into instrument.candidate_set_test_snapshots(
    test_snapshot_key,candidate_set_key,target_key,frozen_test_state,test_state_hash
  )
  values(
    'USC_TEST_'||upper(substr(md5(v_set_key||':support_contract'),1,14)),
    v_set_key,
    'strict_blind_topology_support_v1',
    jsonb_build_object(
      'candidate_count',v_candidate_count,
      'member_count',v_member_count,
      'min_occurrences',p_min_occurrences,
      'min_distinct_units',p_min_distinct_units,
      'semantic_decode','not_opened'
    ),
    v_snapshot_hash
  );

  update instrument.unknown_structure_objects
    set record_status='frozen',frozen_at=now(),updated_at=now()
    where run_id=v_run_id;

  update instrument.runs
    set run_status='frozen',updated_at=now()
    where instrument_run_id=v_run_id;

  return jsonb_build_object(
    'run_id',v_run_id,'run_key',p_run_key,'candidate_set_key',v_set_key,
    'candidates',v_candidate_count,'members',v_member_count,
    'snapshot_hash',v_snapshot_hash,'semantic_decode','not_opened','status','frozen'
  );
end
$function$;
