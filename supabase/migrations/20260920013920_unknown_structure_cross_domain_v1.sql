
create or replace function instrument.discover_unknown_cross_domain_v1(
  p_run_key text,
  p_source_run_a_key text,
  p_source_run_b_key text,
  p_min_support_a integer default 1,
  p_min_support_b integer default 1
)
returns jsonb
language plpgsql
as $function$
declare
  v_run_id bigint;
  v_run_a bigint;
  v_run_b bigint;
  v_status_a text;
  v_status_b text;
  v_candidate_count bigint;
  v_member_count bigint;
  v_set_key text;
  v_snapshot_hash text;
begin
  if p_min_support_a<1 or p_min_support_b<1 then
    raise exception 'Cross-domain support thresholds must be positive';
  end if;

  select instrument_run_id,run_status into v_run_a,v_status_a
  from instrument.runs where run_key=p_source_run_a_key;
  select instrument_run_id,run_status into v_run_b,v_status_b
  from instrument.runs where run_key=p_source_run_b_key;

  if v_run_a is null or v_run_b is null then
    raise exception 'Both source runs must exist';
  end if;
  if v_status_a<>'frozen' or v_status_b<>'frozen' then
    raise exception 'Both source runs must be frozen before cross-domain discovery';
  end if;
  if v_run_a=v_run_b then
    raise exception 'Cross-domain discovery requires distinct source runs';
  end if;

  insert into instrument.runs(
    run_key,run_kind,blindness_class,maximum_prior_load_level,engine_key,
    corpus_scope,boundary_mode,prohibited_feature_families,methodology_version,
    input_snapshot,run_status
  )
  values(
    p_run_key,'validation','strict_blind',2,'unknown_structure_multiscale_v1',
    jsonb_build_object(
      'source_family','cross_domain',
      'source_run_a',p_source_run_a_key,
      'source_run_b',p_source_run_b_key,
      'join_key','topology_family+topology_signature',
      'semantic_decode','prohibited_until_frozen_rejoin'
    ),
    'source_boundaries',
    '["english_gloss","strong_route","song_function","song_object","prior_pattern","blind_target_benchmark"]'::jsonb,
    'noel_unknown_structure_v1',
    jsonb_build_object(
      'source_run_a_id',v_run_a,
      'source_run_b_id',v_run_b
    ),
    'planned'
  )
  returning instrument_run_id into v_run_id;

  with a as (
    select topology_family,topology_signature,count(*)::int support_a
    from instrument.unknown_structure_objects
    where run_id=v_run_a and record_status='frozen'
    group by topology_family,topology_signature
  ),
  b as (
    select topology_family,topology_signature,count(*)::int support_b
    from instrument.unknown_structure_objects
    where run_id=v_run_b and record_status='frozen'
    group by topology_family,topology_signature
  ),
  matched as (
    select a.topology_family,a.topology_signature,a.support_a,b.support_b
    from a join b using(topology_family,topology_signature)
    where a.support_a>=p_min_support_a and b.support_b>=p_min_support_b
  )
  insert into instrument.structure_candidates(
    candidate_key,discovery_run_id,engine_key,anonymous_label,
    neutral_structure,discovery_support,candidate_status
  )
  select
    'USX_'||upper(substr(md5(v_run_id::text||':'||topology_family||':'||topology_signature),1,14)),
    v_run_id,'unknown_structure_multiscale_v1',
    'USX_'||upper(substr(md5(topology_family||':'||topology_signature),1,10)),
    jsonb_build_object(
      'structure_kind','anonymous_cross_domain_topology',
      'topology_family',topology_family,
      'topology_signature',topology_signature,
      'source_run_a_id',v_run_a,
      'source_run_b_id',v_run_b,
      'semantic_decode','not_opened'
    ),
    jsonb_build_object(
      'support_a',support_a,
      'support_b',support_b,
      'pair_support',(support_a::bigint*support_b::bigint),
      'minimum_support_a',p_min_support_a,
      'minimum_support_b',p_min_support_b,
      'discovery_phase','strict_blind_cross_domain_pre_rejoin'
    ),
    'stable_unknown'
  from matched;

  get diagnostics v_candidate_count=row_count;

  insert into instrument.unknown_structure_candidate_members(
    structure_candidate_id,unknown_object_id,member_ordinal,member_role,member_payload
  )
  select
    c.structure_candidate_id,o.unknown_object_id,
    row_number() over(
      partition by c.structure_candidate_id
      order by o.run_id,o.unknown_object_id
    )::int,
    case when o.run_id=v_run_a then 'source_a' else 'source_b' end,
    jsonb_build_object(
      'source_run_id',o.run_id,
      'source_family',o.source_family,
      'object_kind',o.object_kind,
      'scale_key',o.scale_key,
      'semantic_decode','not_opened'
    )
  from instrument.structure_candidates c
  join instrument.unknown_structure_objects o
    on o.run_id in (v_run_a,v_run_b)
   and o.record_status='frozen'
   and o.topology_family=c.neutral_structure->>'topology_family'
   and o.topology_signature=c.neutral_structure->>'topology_signature'
  where c.discovery_run_id=v_run_id;

  get diagnostics v_member_count=row_count;

  v_snapshot_hash := md5(
    coalesce((
      select string_agg(
        c.candidate_key||':'||
        coalesce(c.discovery_support->>'support_a','0')||':'||
        coalesce(c.discovery_support->>'support_b','0'),
        '|' order by c.candidate_key
      )
      from instrument.structure_candidates c
      where c.discovery_run_id=v_run_id
    ),'EMPTY')
  );

  v_set_key := 'USX_SET_'||upper(substr(md5(p_run_key||':cross_domain_set_v1'),1,14));

  insert into instrument.structure_candidate_sets(
    candidate_set_key,method_key,source_run_id,set_purpose,expected_candidate_count,
    set_status,metadata
  )
  values(
    v_set_key,null,v_run_id,'strict_blind_cross_domain_unknown_topology',
    v_candidate_count,'draft',
    jsonb_build_object(
      'semantic_decode','not_opened',
      'source_run_a_id',v_run_a,
      'source_run_b_id',v_run_b,
      'candidate_member_count',v_member_count,
      'candidate_snapshot_hash',v_snapshot_hash,
      'freeze_rule','cross-domain topology match frozen before any source-coordinate or Song rejoin'
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

  update instrument.structure_candidate_sets
    set set_status='frozen'
    where candidate_set_key=v_set_key;

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
