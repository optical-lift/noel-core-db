create or replace function public.wnph_reconstruction_source_packet_v6(
  p_source_package_key text,
  p_target_parent_block_key text,
  p_asset_keys text[] default null
)
returns jsonb
language plpgsql
security definer
stable
set search_path to 'pg_catalog','public','wnph'
as $function$
declare
  v_packet jsonb;
  v_surfaces jsonb;
begin
  v_packet := public.wnph_reconstruction_source_packet_v5(
    p_source_package_key,
    p_target_parent_block_key,
    p_asset_keys
  );

  select coalesce(
    jsonb_agg(
      s.value || jsonb_build_object(
        'observations',
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id',o.id,
              'observation_key',o.observation_key,
              'observation_kind',o.observation_kind,
              'ordinal',o.ordinal,
              'text_candidate',o.text_candidate,
              'coordinate_unit',o.coordinate_unit,
              'x',o.x,'y',o.y,'width',o.width,'height',o.height,
              'confidence',o.confidence,
              'derivation_method',o.derivation_method,
              'source_format',o.source_format,
              'processor',o.processor,
              'external_locator',o.external_locator,
              'metadata',o.metadata
            )
            order by
              case o.observation_kind
                when 'layout_region' then 1
                when 'region' then 2
                when 'line' then 3
                when 'word' then 4
                when 'page_text' then 5
                else 6
              end,
              o.ordinal nulls last,
              o.y nulls last,
              o.x nulls last,
              o.created_at
          )
          from wnph.publication_source_observations o
          where o.source_asset_id=(s.value->>'id')::uuid
            and not exists(
              select 1
              from wnph.publication_source_observations child
              where child.supersedes_observation_id=o.id
            )
        ),'[]'::jsonb)
      )
      order by s.ordinality
    ),
    '[]'::jsonb
  ) into v_surfaces
  from jsonb_array_elements(v_packet->'surfaces') with ordinality as s(value,ordinality);

  return v_packet || jsonb_build_object('surfaces',v_surfaces);
end;
$function$;

revoke all on function public.wnph_reconstruction_source_packet_v6(text,text,text[]) from public,anon,authenticated;
grant execute on function public.wnph_reconstruction_source_packet_v6(text,text,text[]) to service_role;

comment on function public.wnph_reconstruction_source_packet_v6(text,text,text[]) is
'Service-role reconstruction packet v6. Repairs the v2-v5 surface-observation assembly regression caused by an unqualified correlated id reference while preserving the governed semantic source span, observation relations, page-furniture classifications and reading adjudications already carried by v5.';

do $verify$
declare
  v_packet jsonb;
  v_surfaces integer;
  v_observations integer;
  v_relations integer;
  v_classifications integer;
  v_adjudications integer;
  v_ch2_proposals integer;
  v_ch2_blocks integer;
  v_ch1_paragraphs integer;
begin
  v_packet:=public.wnph_reconstruction_source_packet_v6(
    'wish-fairy-and-dewy-dear:canonical-publication-source:v1',
    'dewy:chapter:2:paragraph-stream',
    null
  );

  v_surfaces:=jsonb_array_length(v_packet->'surfaces');
  select coalesce(sum(jsonb_array_length(s.value->'observations')),0)::integer
    into v_observations
  from jsonb_array_elements(v_packet->'surfaces') as s(value);
  v_relations:=jsonb_array_length(v_packet->'observation_relations');
  v_classifications:=jsonb_array_length(v_packet->'observation_classifications');
  v_adjudications:=jsonb_array_length(v_packet->'reading_adjudications');

  if v_surfaces<>10 or v_observations<>242 then
    raise exception 'WNPH reconstruction packet v6 expected 10 Chapter II surfaces and 242 active observations; got % surfaces and % observations',v_surfaces,v_observations;
  end if;
  if v_relations<>189 or v_classifications<>11 or v_adjudications<>3 then
    raise exception 'WNPH reconstruction packet v6 governance mismatch: relations %, classifications %, adjudications %',v_relations,v_classifications,v_adjudications;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(v_packet->'surfaces') s,
         jsonb_array_elements(s->'observations') o
    where s->>'asset_key'='dewy:loc:source-surface:0021'
      and o->>'observation_kind'='line'
      and (o->>'ordinal')::integer=20
      and o->>'text_candidate'='heresy,'
  ) then
    raise exception 'WNPH reconstruction packet v6 lost preserved LOC heresy observation';
  end if;

  select count(*) into v_ch2_proposals
  from wnph.publication_source_reconstruction_proposals p
  join wnph.publication_source_blocks parent on parent.id=p.target_parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals n where n.supersedes_proposal_id=p.id);

  select count(*) into v_ch2_blocks
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:2:paragraph-stream'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  select count(*) into v_ch1_paragraphs
  from wnph.publication_source_blocks b
  join wnph.publication_source_blocks parent on parent.id=b.parent_block_id
  where parent.block_key='dewy:chapter:1:paragraph-stream'
    and b.block_type='paragraph'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id);

  if v_ch2_proposals<>0 or v_ch2_blocks<>0 or v_ch1_paragraphs<>24 then
    raise exception 'WNPH packet v6 migration changed reading state: ch2 proposals %, ch2 blocks %, ch1 paragraphs %',v_ch2_proposals,v_ch2_blocks,v_ch1_paragraphs;
  end if;
end;
$verify$;