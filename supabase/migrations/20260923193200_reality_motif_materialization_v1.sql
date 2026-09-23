-- Reality Motif materialization and recurrence v1

CREATE OR REPLACE FUNCTION draft.materialize_reality_motifs_v1(p_occurrence_id bigint, p_min_edges integer DEFAULT 2, p_max_edges integer DEFAULT 5, p_replace boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_occurrence_key text;
  v_independence_key text;
  v_candidate_count integer;
  v_instance_count integer;
  v_motif_count integer;
begin
  select
    occurrence_key,
    coalesce(metadata->>'independenceKey',occurrence_key)
  into v_occurrence_key,v_independence_key
  from draft.reality_occurrences
  where occurrence_id=p_occurrence_id;

  if v_occurrence_key is null then
    raise exception 'Unknown occurrence_id %',p_occurrence_id;
  end if;

  if p_replace then
    delete from draft.reality_motif_instances
    where occurrence_id=p_occurrence_id;
  end if;

  create temporary table if not exists pg_temp.reality_motif_candidates_work (
    instance_key text,
    edge_count integer,
    node_count integer,
    edge_keys text[],
    node_keys text[],
    canonical_signature text,
    role_signature text,
    coordinate_groups text[],
    witness_keys text[],
    structure jsonb
  ) on commit drop;

  truncate pg_temp.reality_motif_candidates_work;

  insert into pg_temp.reality_motif_candidates_work
  select *
  from intelligence.enumerate_reality_motif_candidates_v1(
    p_occurrence_id,p_min_edges,p_max_edges
  );

  get diagnostics v_candidate_count = row_count;

  insert into draft.reality_motif_registry(
    motif_key,
    structure_version,
    canonical_signature,
    edge_count,
    node_count,
    motif_status,
    metadata,
    first_seen_at,
    last_seen_at
  )
  select distinct on (c.canonical_signature)
    'motif:'||c.edge_count::text||':'||md5(c.canonical_signature),
    'bounded_typed_v1',
    c.canonical_signature,
    c.edge_count,
    c.node_count,
    'candidate',
    jsonb_build_object(
      'canonicalization','degree_typed_structural_signature',
      'exemplarStructure',c.structure
    ),
    now(),
    now()
  from pg_temp.reality_motif_candidates_work c
  order by c.canonical_signature,c.instance_key
  on conflict (structure_version,canonical_signature) do update set
    last_seen_at=now(),
    updated_at=now();

  insert into draft.reality_motif_instances(
    motif_id,
    occurrence_id,
    instance_key,
    independence_key,
    edge_count,
    node_count,
    edge_keys,
    node_keys,
    coordinate_groups,
    witness_keys,
    role_signature,
    structure,
    instance_status,
    metadata
  )
  select
    mr.motif_id,
    p_occurrence_id,
    c.instance_key,
    v_independence_key,
    c.edge_count,
    c.node_count,
    c.edge_keys,
    c.node_keys,
    c.coordinate_groups,
    c.witness_keys,
    c.role_signature,
    c.structure,
    'materialized',
    jsonb_build_object(
      'enumerator','intelligence.enumerate_reality_motif_candidates_v1',
      'minEdges',greatest(p_min_edges,2),
      'maxEdges',least(greatest(p_max_edges,2),5)
    )
  from pg_temp.reality_motif_candidates_work c
  join draft.reality_motif_registry mr
    on mr.structure_version='bounded_typed_v1'
   and mr.canonical_signature=c.canonical_signature
  on conflict (instance_key) do update set
    motif_id=excluded.motif_id,
    occurrence_id=excluded.occurrence_id,
    independence_key=excluded.independence_key,
    edge_count=excluded.edge_count,
    node_count=excluded.node_count,
    edge_keys=excluded.edge_keys,
    node_keys=excluded.node_keys,
    coordinate_groups=excluded.coordinate_groups,
    witness_keys=excluded.witness_keys,
    role_signature=excluded.role_signature,
    structure=excluded.structure,
    instance_status=excluded.instance_status,
    metadata=excluded.metadata,
    updated_at=now();

  select count(*) into v_instance_count
  from draft.reality_motif_instances
  where occurrence_id=p_occurrence_id;

  select count(distinct motif_id) into v_motif_count
  from draft.reality_motif_instances
  where occurrence_id=p_occurrence_id;

  return jsonb_build_object(
    'occurrenceId',p_occurrence_id,
    'occurrenceKey',v_occurrence_key,
    'independenceKey',v_independence_key,
    'candidateCount',v_candidate_count,
    'instanceCount',v_instance_count,
    'distinctMotifCount',v_motif_count
  );
end;
$function$
;

comment on function draft.materialize_reality_motifs_v1(bigint,integer,integer,boolean) is
'Materializes bounded label-stripped structural motifs for one Reality Occurrence. Motif identity comes only from structural signature; native labels and witness identities remain instance-level recoverable context.';

create or replace view intelligence.v_reality_motif_recurrence_v1
with (security_invoker=true)
as
 WITH witness_diversity AS (
         SELECT i_1.motif_id,
            count(DISTINCT w_1.w)::integer AS witness_key_count
           FROM draft.reality_motif_instances i_1
             CROSS JOIN LATERAL unnest(i_1.witness_keys) w_1(w)
          GROUP BY i_1.motif_id
        ), role_variants AS (
         SELECT reality_motif_instances.motif_id,
            count(DISTINCT reality_motif_instances.role_signature)::integer AS role_signature_count
           FROM draft.reality_motif_instances
          GROUP BY reality_motif_instances.motif_id
        )
 SELECT m.motif_id,
    m.motif_key,
    m.structure_version,
    m.edge_count,
    m.node_count,
    m.canonical_signature,
    m.motif_status,
    count(i.motif_instance_id)::integer AS instance_count,
    count(DISTINCT i.occurrence_id)::integer AS occurrence_count,
    count(DISTINCT i.independence_key)::integer AS independent_occurrence_count,
    COALESCE(w.witness_key_count, 0) AS witness_key_count,
    COALESCE(rv.role_signature_count, 0) AS role_signature_count,
    max(cardinality(i.coordinate_groups)) AS max_coordinate_group_span,
        CASE
            WHEN count(DISTINCT i.independence_key) >= 2 THEN 'independent_recurrence'::text
            WHEN count(DISTINCT i.occurrence_id) >= 2 THEN 'repeated_nonindependent'::text
            WHEN count(i.motif_instance_id) >= 2 THEN 'repeated_within_occurrence'::text
            ELSE 'singleton'::text
        END AS recurrence_state,
    m.first_seen_at,
    m.last_seen_at,
    m.metadata
   FROM draft.reality_motif_registry m
     LEFT JOIN draft.reality_motif_instances i USING (motif_id)
     LEFT JOIN witness_diversity w USING (motif_id)
     LEFT JOIN role_variants rv USING (motif_id)
  GROUP BY m.motif_id, m.motif_key, m.structure_version, m.edge_count, m.node_count, m.canonical_signature, m.motif_status, w.witness_key_count, rv.role_signature_count, m.first_seen_at, m.last_seen_at, m.metadata;;

comment on view intelligence.v_reality_motif_recurrence_v1 is
'Recurrence audit for structural motifs. Independent occurrence count is distinct from raw occurrence count and within-occurrence repetition.';

CREATE OR REPLACE FUNCTION draft.refresh_reality_motif_compositions_v1(p_occurrence_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_pairs integer;
begin
  if p_occurrence_id is null then
    delete from draft.reality_motif_compositions
    where metadata->>'generatedBy'='refresh_reality_motif_compositions_v1';
  else
    delete from draft.reality_motif_compositions c
    where c.metadata->>'generatedBy'='refresh_reality_motif_compositions_v1'
      and exists (
        select 1
        from draft.reality_motif_instances p
        where p.motif_id=c.parent_motif_id
          and p.occurrence_id=p_occurrence_id
      );
  end if;

  insert into draft.reality_motif_compositions(
    parent_motif_id,
    child_motif_id,
    composition_role,
    composition_status,
    evidence_count,
    metadata
  )
  select
    p.motif_id,
    c.motif_id,
    'contains_edge_subgraph',
    'candidate',
    count(distinct p.independence_key)::integer,
    jsonb_build_object(
      'generatedBy','refresh_reality_motif_compositions_v1',
      'instancePairCount',count(*)::integer
    )
  from draft.reality_motif_instances p
  join draft.reality_motif_instances c
    on c.occurrence_id=p.occurrence_id
   and c.edge_count<p.edge_count
   and c.edge_keys<@p.edge_keys
  where p.motif_id<>c.motif_id
    and (p_occurrence_id is null or p.occurrence_id=p_occurrence_id)
  group by p.motif_id,c.motif_id
  on conflict (parent_motif_id,child_motif_id,composition_role) do update set
    composition_status=excluded.composition_status,
    evidence_count=excluded.evidence_count,
    metadata=excluded.metadata,
    updated_at=now();

  get diagnostics v_pairs = row_count;

  return jsonb_build_object(
    'occurrenceId',p_occurrence_id,
    'compositionPairCount',v_pairs
  );
end;
$function$
;

comment on function draft.refresh_reality_motif_compositions_v1(bigint) is
'Builds candidate motif composition edges when a larger motif instance contains all edges of a smaller motif instance in the same occurrence. Evidence count uses independence families.';

revoke all on function draft.materialize_reality_motifs_v1(bigint,integer,integer,boolean)
  from public,anon,authenticated;
revoke all on intelligence.v_reality_motif_recurrence_v1 from anon,authenticated;
revoke all on function draft.refresh_reality_motif_compositions_v1(bigint)
  from public,anon,authenticated;

grant execute on function draft.materialize_reality_motifs_v1(bigint,integer,integer,boolean)
  to service_role;
grant select on intelligence.v_reality_motif_recurrence_v1 to service_role;
grant execute on function draft.refresh_reality_motif_compositions_v1(bigint)
  to service_role;
