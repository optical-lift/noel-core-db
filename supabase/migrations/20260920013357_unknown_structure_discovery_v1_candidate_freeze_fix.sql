
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
    set_status,metadata
  )
  values(
    v_set_key,null,v_run_id,'strict_blind_unknown_structure_topology',
    v_candidate_count,'draft',
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

  update instrument.structure_candidate_sets
    set set_status='frozen'
    where candidate_set_key=v_set_key;

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
