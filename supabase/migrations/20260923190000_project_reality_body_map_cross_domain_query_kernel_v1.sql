begin;

-- Cross-domain body-map vocabulary query kernel v1.
--
-- Governing law:
--   non-discriminating retrieval; discriminating provenance.
--
-- A body-map selection records what the human selected or reported.
-- It does not establish diagnosis, mechanism, causation, treatment,
-- theological meaning, framework equivalence, or evidence parity.

create table if not exists draft.reality_query_dimension_registry (
  dimension_key text primary key,
  display_name text not null,
  dimension_family text not null,
  value_mode text not null,
  neutral_definition text not null,
  ui_selectable boolean not null default true,
  status text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (value_mode in ('controlled_text','free_text','numeric','boolean'))
);

comment on table draft.reality_query_dimension_registry is
'Neutral dimensions accepted by cross-domain reality queries. A dimension describes what the user marked or reported; it does not establish a diagnosis, mechanism, interpretation, or treatment.';

insert into draft.reality_query_dimension_registry
(dimension_key,display_name,dimension_family,value_mode,neutral_definition,ui_selectable,status)
values
('body_region','Body region','body','controlled_text','An anatomical or practitioner body-map region selected by the user.',true,'active'),
('laterality','Laterality','body','controlled_text','The side or laterality attached to a selected body region.',true,'active'),
('body_region_side','Body region + side','body','controlled_text','A compound region/laterality value used for exact side-specific matching.',false,'active'),
('sensation','Sensation','phenomenology','controlled_text','A person-reported bodily sensation without causal interpretation.',true,'active'),
('reported_symptom','Reported symptom','phenomenology','controlled_text','A person-reported symptom label without diagnostic promotion.',true,'active'),
('quality','Quality','phenomenology','controlled_text','A descriptive quality attached to a reported or observed phenomenon.',true,'active'),
('temporal_pattern','Temporal pattern','time','controlled_text','How a phenomenon behaves over time, such as intermittent or continuous.',true,'active'),
('frequency','Frequency','time','controlled_text','How often a phenomenon occurs.',true,'active'),
('onset','Onset','time','controlled_text','How or when a phenomenon began, without causal interpretation.',true,'active'),
('intensity','Intensity','phenomenology','controlled_text','A reported or measured intensity description.',true,'active'),
('trigger','Trigger / context','context','controlled_text','A context reported as temporally or experientially associated with a phenomenon.',true,'active'),
('observation_domain','Observation domain','observation','controlled_text','The observation domain recorded by an existing Noel phenomenon facet.',false,'active'),
('context_domain','Context domain','context','controlled_text','The contextual domain recorded by an existing Noel phenomenon facet.',false,'active'),
('relationship_process','Relationship process','context','controlled_text','A relationship-process descriptor recorded by an existing Noel phenomenon facet.',false,'active'),
('affect','Affect','phenomenology','controlled_text','An affective descriptor recorded by an existing Noel phenomenon facet.',false,'active')
on conflict (dimension_key) do update set
  display_name=excluded.display_name,
  dimension_family=excluded.dimension_family,
  value_mode=excluded.value_mode,
  neutral_definition=excluded.neutral_definition,
  ui_selectable=excluded.ui_selectable,
  status=excluded.status,
  updated_at=now();

create table if not exists draft.reality_query_value_registry (
  dimension_key text not null references draft.reality_query_dimension_registry(dimension_key) on update cascade on delete restrict,
  value_key text not null,
  display_label text not null,
  neutral_definition text,
  status text not null default 'working',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (dimension_key,value_key)
);

comment on table draft.reality_query_value_registry is
'UI-facing neutral input vocabulary for structured reality queries. Presence here means selectable input vocabulary only; it does not make the value a medical, theological, or practitioner claim.';

insert into draft.reality_query_value_registry
(dimension_key,value_key,display_label,neutral_definition,status)
values
('sensation','pressure','Pressure','A person-reported sense described as pressure.','working'),
('reported_symptom','dizziness','Dizziness','A person-reported experience described as dizziness.','working'),
('sensation','ache','Ache','A person-reported sensation described as an ache.','working'),
('temporal_pattern','intermittent','Intermittent','Occurs at intervals rather than continuously.','working')
on conflict (dimension_key,value_key) do update set
  display_label=excluded.display_label,
  neutral_definition=excluded.neutral_definition,
  status=excluded.status,
  updated_at=now();

create table if not exists draft.reality_object_query_descriptors (
  descriptor_id bigint generated by default as identity primary key,
  object_type text not null,
  object_id text not null,
  dimension_key text not null references draft.reality_query_dimension_registry(dimension_key) on update cascade on delete restrict,
  dimension_value text not null,
  normalized_value text not null,
  relation_type text not null default 'describes',
  source_basis text not null,
  framework_key text references draft.reality_frameworks(framework_key) on update cascade on delete set null,
  evidence_ref jsonb not null default '{}'::jsonb,
  confidence text,
  rationale text,
  status text not null default 'working',
  metadata jsonb not null default '{}'::jsonb,
  scope_region_key text references practice.body_regions(region_key) on update cascade on delete restrict,
  scope_side text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (scope_side is null or scope_side in ('left','right','bilateral','unspecified'))
);

comment on table draft.reality_object_query_descriptors is
'Cross-domain query annotations that connect an existing Noel object to a neutral query dimension. This table does not copy or replace source authority and must preserve source/evidence custody for every mapping.';

comment on column draft.reality_object_query_descriptors.scope_region_key is
'Optional anatomical scope. A feature mapping scoped to one region may satisfy only a query selection on that region or a selected ancestor of it.';

comment on column draft.reality_object_query_descriptors.scope_side is
'Optional laterality scope. A feature mapping scoped to one side may satisfy only compatible laterality.';

create unique index if not exists reality_object_query_descriptors_uq
on draft.reality_object_query_descriptors
(
  object_type,
  object_id,
  dimension_key,
  normalized_value,
  relation_type,
  coalesce(framework_key,''),
  coalesce(scope_region_key,''),
  coalesce(scope_side,'')
);

create index if not exists reality_object_query_descriptors_lookup_idx
on draft.reality_object_query_descriptors(dimension_key,normalized_value);

create index if not exists reality_object_query_descriptors_object_idx
on draft.reality_object_query_descriptors(object_type,object_id);

create index if not exists reality_object_query_descriptors_scope_idx
on draft.reality_object_query_descriptors(scope_region_key,scope_side,dimension_key,normalized_value);

alter table draft.reality_query_dimension_registry enable row level security;
alter table draft.reality_query_value_registry enable row level security;
alter table draft.reality_object_query_descriptors enable row level security;

revoke all on draft.reality_query_dimension_registry from anon, authenticated;
revoke all on draft.reality_query_value_registry from anon, authenticated;
revoke all on draft.reality_object_query_descriptors from anon, authenticated;

create or replace view intelligence.v_body_region_hierarchy_v1
with (security_invoker=true)
as
with recursive region_tree as (
  select br.region_key ancestor_region_key, br.region_key descendant_region_key, 0::int depth
  from practice.body_regions br
  union all
  select rt.ancestor_region_key, child.region_key, rt.depth+1
  from region_tree rt
  join practice.body_regions child on child.parent_region_key=rt.descendant_region_key
)
select distinct ancestor_region_key,descendant_region_key,depth
from region_tree;

comment on view intelligence.v_body_region_hierarchy_v1 is
'Expands a selected body region to itself and nested descendant regions for retrieval only. Anatomical containment does not establish causal or diagnostic relationships.';

create or replace view intelligence.v_universal_vocabulary_index_v1
with (security_invoker=true)
as
select
  'body_region'::text object_type,
  br.region_key::text object_id,
  br.region_name::text display_label,
  'anatomical_region'::text object_kind,
  'practice_body_map'::text source_domain,
  'neutral_anatomy'::text source_jurisdiction,
  null::text framework_key,
  null::text framework_name,
  'active'::text source_status,
  br.notes::text definition_text,
  jsonb_build_object('parent_region_key',br.parent_region_key,'laterality_allowed',br.laterality_allowed) metadata
from practice.body_regions br
union all
select
  'reality_phenomenon',p.phenomenon_key,p.preferred_label,p.phenomenon_kind,
  'reality_phenomena','neutral_observation',null,null,p.phenomenon_status,p.neutral_definition,
  p.metadata || jsonb_build_object('does_not_establish',p.does_not_establish,'observation_mode',p.observation_mode)
from draft.reality_phenomena p
union all
select
  'framework_concept',c.concept_key,c.preferred_label,c.concept_kind,
  'reality_framework_concepts','framework_native',c.framework_key,f.framework_name,
  c.concept_status,c.native_definition,
  c.metadata || jsonb_build_object(
    'source_language',c.source_language,'native_id',c.native_id,
    'framework_family',f.framework_family,'framework_kind',f.framework_kind
  )
from draft.reality_framework_concepts c
join draft.reality_frameworks f using(framework_key)
union all
select
  'function',f.function_key,f.function_name,'function','function_registry','noel_function',
  null,null,f.status,f.working_definition,
  jsonb_build_object(
    'before_state',f.before_state,'operation',f.operation,'after_state',f.after_state,
    'lawful_source',f.lawful_source,'intended_fruit',f.intended_fruit,
    'failure_mode',f.failure_mode,'clarity_state',f.clarity_state
  )
from draft.function_registry f
union all
select
  'function_term',t.term_key,t.term,t.term_kind,'function_terms','cross_domain_term',
  null,null,t.status,coalesce(t.noel_working_definition,t.meaning_as_used_by_source),
  jsonb_build_object(
    'normalized_term',t.normalized_term,'domain',t.domain,'source_tradition',t.source_tradition,
    'aliases',t.aliases,'usage_policy',t.usage_policy,'does_not_establish',t.does_not_establish,
    'required_questions',t.required_questions,'definition_basis',t.definition_basis,'clarity_state',t.clarity_state
  )
from draft.function_terms t
union all
select
  'practice_lexicon_term',l.term_id::text,l.preferred_label,l.term_kind,
  'practice_lexicon','practitioner_vocabulary',null,null,l.status,l.operator_definition,
  l.metadata || jsonb_build_object(
    'term_key',l.term_key,'usage_rule',l.usage_rule,
    'external_definition_note',l.external_definition_note,'source_basis',l.source_basis,
    'aliases',coalesce((
      select jsonb_agg(a.alias order by a.alias)
      from practice.lexicon_aliases a
      where a.term_id=l.term_id
    ),'[]'::jsonb)
  )
from practice.lexicon_terms l
union all
select
  'song_object',s.song_object_id::text,s.object_name,s.object_type,'song_objects','song',
  null,null,s.object_status,s.one_sentence_claim,
  jsonb_build_object(
    'provisional_function_lane',s.provisional_function_lane,
    'mainstream_rival_reading',s.mainstream_rival_reading,'notes',s.notes
  )
from draft.song_objects s
union all
select
  'canon_organic_term',c.term_key,
  coalesce(nullif(c.transliteration,''),nullif(c.lemma,''),c.neutral_gloss),
  c.term_kind,'canon_organic_terms','canon_vocabulary',null,null,c.source_status,c.neutral_gloss,
  jsonb_build_object(
    'language_code',c.language_code,'lemma',c.lemma,'transliteration',c.transliteration,
    'strong_id',c.strong_id,'definition_ceiling',c.definition_ceiling,'notes',c.notes
  )
from draft.canon_organic_terms c
union all
select
  'research_claim',r.claim_id::text,r.claim_title,r.claim_kind,'research_claims','research_claim',
  null,null,r.claim_status,r.short_claim,
  jsonb_build_object(
    'claim_key',r.claim_key,'current_category',r.current_category,'confidence',r.confidence,
    'live_test',r.live_test,'evidence_needed',r.evidence_needed,
    'strengthens_if',r.strengthens_if,'weakens_if',r.weakens_if
  )
from draft.research_claims r
union all
select
  'celestial_function_hypothesis',h.hypothesis_id::text,h.candidate_function_label,h.hypothesis_kind,
  'celestial_function_hypotheses','celestial_research_hypothesis',null,null,
  h.hypothesis_status,h.candidate_definition,
  jsonb_build_object(
    'hypothesis_key',h.hypothesis_key,'scope_object_type',h.scope_object_type,
    'scope_object_id',h.scope_object_id,'nearest_function_key',h.nearest_function_key,
    'relationship_to_existing_function',h.relationship_to_existing_function,
    'rival_hypothesis',h.rival_hypothesis,'confidence',h.confidence,
    'promotion_gate',h.promotion_gate,'status',h.status
  )
from draft.celestial_function_hypotheses h
union all
select
  'celestial_role_hypothesis',h.role_hypothesis_id::text,h.candidate_label,h.hypothesis_kind,
  'celestial_role_hypotheses','celestial_research_hypothesis',null,null,
  h.hypothesis_status,h.candidate_definition,
  jsonb_build_object(
    'hypothesis_key',h.hypothesis_key,'scope_object_type',h.scope_object_type,
    'scope_object_id',h.scope_object_id,'rival_hypothesis',h.rival_hypothesis,
    'confidence',h.confidence,'promotion_gate',h.promotion_gate,'status',h.status
  )
from draft.celestial_role_hypotheses h;

comment on view intelligence.v_universal_vocabulary_index_v1 is
'Cross-domain vocabulary projection. Rows retain native jurisdiction and status. Inclusion means retrievable vocabulary, not equivalence, truth, diagnosis, recommendation, or evidence parity.';

create or replace view intelligence.v_universal_vocabulary_dimension_map_v2
with (security_invoker=true)
as
select
  d.object_type,d.object_id,d.dimension_key,d.dimension_value,d.normalized_value,
  d.relation_type,d.source_basis,d.confidence,d.status,d.scope_region_key,d.scope_side,
  d.metadata || jsonb_build_object(
    'descriptor_id',d.descriptor_id,'framework_key',d.framework_key,
    'evidence_ref',d.evidence_ref,'rationale',d.rationale
  ) metadata
from draft.reality_object_query_descriptors d
union all
select
  'body_region',br.region_key,'body_region',br.region_key,lower(br.region_key),
  'self','practice.body_regions',null,'active',br.region_key,null::text,
  jsonb_build_object('region_name',br.region_name,'parent_region_key',br.parent_region_key)
from practice.body_regions br
union all
select
  'reality_phenomenon',pf.phenomenon_key,pf.facet_type,pf.facet_value,
  lower(regexp_replace(trim(coalesce(pf.normalized_value,pf.facet_value)),'\s+','_','g')),
  'phenomenon_facet',pf.facet_source,pf.confidence,pf.facet_status,
  case
    when pf.facet_type='body_region'
      then lower(regexp_replace(trim(coalesce(pf.normalized_value,pf.facet_value)),'\s+','_','g'))
    else scope.scope_region_key
  end,
  null::text,
  pf.metadata || jsonb_build_object('rationale',pf.rationale)
from draft.reality_phenomenon_facets pf
left join lateral (
  select case
    when count(distinct lower(regexp_replace(trim(coalesce(p2.normalized_value,p2.facet_value)),'\s+','_','g')))=1
      then min(lower(regexp_replace(trim(coalesce(p2.normalized_value,p2.facet_value)),'\s+','_','g')))
    else null
  end scope_region_key
  from draft.reality_phenomenon_facets p2
  where p2.phenomenon_key=pf.phenomenon_key
    and p2.facet_type='body_region'
    and p2.facet_status<>'retired'
) scope on true
union all
select
  'framework_concept',l.concept_key,pf.facet_type,pf.facet_value,
  lower(regexp_replace(trim(coalesce(pf.normalized_value,pf.facet_value)),'\s+','_','g')),
  'framework_concept_via_phenomenon',
  'draft.reality_framework_concept_phenomenon_links -> draft.reality_phenomenon_facets',
  l.confidence,l.mapping_status,
  case
    when pf.facet_type='body_region'
      then lower(regexp_replace(trim(coalesce(pf.normalized_value,pf.facet_value)),'\s+','_','g'))
    else scope.scope_region_key
  end,
  null::text,
  l.metadata || jsonb_build_object(
    'phenomenon_key',l.phenomenon_key,'mapping_relation',l.mapping_relation,
    'mapping_rationale',l.rationale,'facet_source',pf.facet_source
  )
from draft.reality_framework_concept_phenomenon_links l
join draft.reality_phenomenon_facets pf using(phenomenon_key)
left join lateral (
  select case
    when count(distinct lower(regexp_replace(trim(coalesce(p2.normalized_value,p2.facet_value)),'\s+','_','g')))=1
      then min(lower(regexp_replace(trim(coalesce(p2.normalized_value,p2.facet_value)),'\s+','_','g')))
    else null
  end scope_region_key
  from draft.reality_phenomenon_facets p2
  where p2.phenomenon_key=l.phenomenon_key
    and p2.facet_type='body_region'
    and p2.facet_status<>'retired'
) scope on true
union all
select
  'function',l.function_key,'body_region',l.region_key,lower(l.region_key),
  l.relation_type,'practice.body_region_function_links',l.confidence,l.status,
  l.region_key,l.side,
  jsonb_build_object('side',l.side,'evidence_basis',l.evidence_basis,'rationale',l.rationale)
from practice.body_region_function_links l
union all
select
  'function',l.function_key,'body_region_side',l.region_key||':'||l.side,lower(l.region_key||':'||l.side),
  l.relation_type,'practice.body_region_function_links',l.confidence,l.status,
  l.region_key,l.side,
  jsonb_build_object('region_key',l.region_key,'side',l.side,'evidence_basis',l.evidence_basis,'rationale',l.rationale)
from practice.body_region_function_links l
where l.side is not null
union all
select
  'function_term',ftl.term_key,'body_region',brl.region_key,lower(brl.region_key),
  'term_via_function_body_link','draft.function_term_links -> practice.body_region_function_links',
  coalesce(ftl.confidence,brl.confidence),
  case when ftl.status='active' and brl.status='active' then 'active' else coalesce(ftl.status,brl.status) end,
  brl.region_key,brl.side,
  jsonb_build_object(
    'function_key',ftl.function_key,'function_relation',ftl.relation_type,
    'body_relation',brl.relation_type,'side',brl.side
  )
from draft.function_term_links ftl
join practice.body_region_function_links brl using(function_key)
union all
select
  'practice_lexicon_term',lfl.term_id::text,'body_region',brl.region_key,lower(brl.region_key),
  'practice_term_via_function_body_link','practice.lexicon_function_links -> practice.body_region_function_links',
  coalesce(lfl.confidence,brl.confidence),
  case when lfl.link_status='active' and brl.status='active' then 'active' else coalesce(lfl.link_status,brl.status) end,
  brl.region_key,brl.side,
  lfl.metadata || jsonb_build_object(
    'function_key',lfl.function_key,'body_relation',brl.relation_type,
    'side',brl.side,'evidence_basis',lfl.evidence_basis
  )
from practice.lexicon_function_links lfl
join practice.body_region_function_links brl using(function_key)
union all
select
  'song_object',l.song_object_id::text,'body_region',l.region_key,lower(l.region_key),
  l.relation_type,'practice.body_region_song_object_links',l.confidence,l.status,
  l.region_key,l.side,
  jsonb_build_object('side',l.side,'evidence_basis',l.evidence_basis,'rationale',l.rationale)
from practice.body_region_song_object_links l
union all
select
  'celestial_function_hypothesis',h.hypothesis_id::text,'body_region',brl.region_key,lower(brl.region_key),
  'candidate_hypothesis_via_nearest_function',
  'draft.celestial_function_hypotheses.nearest_function_key -> practice.body_region_function_links',
  coalesce(h.confidence,brl.confidence),h.hypothesis_status,
  brl.region_key,brl.side,
  jsonb_build_object(
    'nearest_function_key',h.nearest_function_key,'body_relation',brl.relation_type,
    'side',brl.side,'hypothesis_status',h.hypothesis_status
  )
from draft.celestial_function_hypotheses h
join practice.body_region_function_links brl on brl.function_key=h.nearest_function_key
where h.nearest_function_key is not null;

comment on view intelligence.v_universal_vocabulary_dimension_map_v2 is
'Region-aware query mappings. Feature descriptors carry optional anatomical/laterality scope so a feature attached to one body-map selection cannot satisfy another body region by word overlap alone.';

create or replace function intelligence.body_map_query_dimensions_v1(p_query jsonb)
returns table(
  selection_no integer,
  region_key text,
  side text,
  dimension_key text,
  dimension_value text,
  normalized_value text,
  source_path text
)
language plpgsql
security invoker
stable
set search_path=''
as $function$
declare
  v_selection jsonb;
  v_feature jsonb;
  v_value jsonb;
  v_ord bigint;
  v_region text;
  v_side text;
  v_dimension text;
  v_dimension_value text;
  v_laterality_allowed boolean;
begin
  if p_query is null
     or jsonb_typeof(p_query)<>'object'
     or jsonb_typeof(p_query->'selections')<>'array'
     or jsonb_array_length(p_query->'selections')=0 then
    raise exception 'body-map query requires a non-empty selections array';
  end if;

  for v_selection,v_ord in
    select value,ordinality
    from jsonb_array_elements(p_query->'selections') with ordinality
  loop
    if jsonb_typeof(v_selection)<>'object' then
      raise exception 'selection % must be an object',v_ord;
    end if;

    v_region:=nullif(trim(v_selection->>'region_key'),'');
    if v_region is null then
      raise exception 'selection % requires region_key',v_ord;
    end if;

    select br.laterality_allowed into v_laterality_allowed
    from practice.body_regions br
    where br.region_key=v_region;

    if not found then
      raise exception 'unknown body region: %',v_region;
    end if;

    v_side:=nullif(lower(trim(v_selection->>'side')),'');
    if v_side is not null and v_side not in ('left','right','bilateral','unspecified') then
      raise exception 'unsupported side "%" for region %',v_side,v_region;
    end if;

    if coalesce(v_laterality_allowed,false)=false and v_side in ('left','right','bilateral') then
      raise exception 'region % does not permit laterality in the current body-region registry',v_region;
    end if;

    selection_no:=v_ord::integer;
    region_key:=v_region;
    side:=v_side;
    dimension_key:='body_region';
    dimension_value:=v_region;
    normalized_value:=lower(v_region);
    source_path:=format('selections[%s].region_key',v_ord-1);
    return next;

    if v_side is not null and v_side<>'unspecified' then
      selection_no:=v_ord::integer;
      region_key:=v_region;
      side:=v_side;
      dimension_key:='laterality';
      dimension_value:=v_side;
      normalized_value:=v_side;
      source_path:=format('selections[%s].side',v_ord-1);
      return next;

      selection_no:=v_ord::integer;
      region_key:=v_region;
      side:=v_side;
      dimension_key:='body_region_side';
      dimension_value:=v_region||':'||v_side;
      normalized_value:=lower(v_region||':'||v_side);
      source_path:=format('selections[%s].side',v_ord-1);
      return next;
    end if;

    if v_selection ? 'features' then
      if jsonb_typeof(v_selection->'features')<>'array' then
        raise exception 'selection %.features must be an array',v_ord;
      end if;

      for v_feature in select value from jsonb_array_elements(v_selection->'features')
      loop
        if jsonb_typeof(v_feature)<>'object' then
          raise exception 'selection %.features entries must be objects',v_ord;
        end if;

        v_dimension:=nullif(trim(v_feature->>'dimension_key'),'');
        v_dimension_value:=nullif(trim(v_feature->>'value'),'');
        if v_dimension is null or v_dimension_value is null then
          raise exception 'selection %.features entries require dimension_key and value',v_ord;
        end if;

        if not exists(
          select 1
          from draft.reality_query_dimension_registry d
          where d.dimension_key=v_dimension and d.status<>'retired'
        ) then
          raise exception 'unknown query dimension: %',v_dimension;
        end if;

        selection_no:=v_ord::integer;
        region_key:=v_region;
        side:=v_side;
        dimension_key:=v_dimension;
        dimension_value:=v_dimension_value;
        normalized_value:=lower(regexp_replace(trim(v_dimension_value),'\s+','_','g'));
        source_path:=format('selections[%s].features',v_ord-1);
        return next;
      end loop;
    end if;

    if v_selection ? 'qualities' then
      if jsonb_typeof(v_selection->'qualities')<>'array' then
        raise exception 'selection %.qualities must be an array',v_ord;
      end if;
      for v_value in select value from jsonb_array_elements(v_selection->'qualities')
      loop
        v_dimension_value:=nullif(trim(v_value #>> '{}'),'');
        if v_dimension_value is not null then
          selection_no:=v_ord::integer;
          region_key:=v_region;
          side:=v_side;
          dimension_key:='quality';
          dimension_value:=v_dimension_value;
          normalized_value:=lower(regexp_replace(trim(v_dimension_value),'\s+','_','g'));
          source_path:=format('selections[%s].qualities',v_ord-1);
          return next;
        end if;
      end loop;
    end if;

    if v_selection ? 'temporal' then
      if jsonb_typeof(v_selection->'temporal')<>'array' then
        raise exception 'selection %.temporal must be an array',v_ord;
      end if;
      for v_value in select value from jsonb_array_elements(v_selection->'temporal')
      loop
        v_dimension_value:=nullif(trim(v_value #>> '{}'),'');
        if v_dimension_value is not null then
          selection_no:=v_ord::integer;
          region_key:=v_region;
          side:=v_side;
          dimension_key:='temporal_pattern';
          dimension_value:=v_dimension_value;
          normalized_value:=lower(regexp_replace(trim(v_dimension_value),'\s+','_','g'));
          source_path:=format('selections[%s].temporal',v_ord-1);
          return next;
        end if;
      end loop;
    end if;
  end loop;
end;
$function$;

comment on function intelligence.body_map_query_dimensions_v1(jsonb) is
'Validates and normalizes a body-map query into neutral dimensions. It preserves what was selected and does not infer diagnosis, mechanism, causation, or treatment.';

create or replace function intelligence.search_body_map_vocabulary_v2(
  p_query jsonb,
  p_limit integer default 100
)
returns table(
  object_type text,
  object_id text,
  display_label text,
  object_kind text,
  source_domain text,
  source_jurisdiction text,
  framework_key text,
  framework_name text,
  source_status text,
  definition_text text,
  matched_region_count integer,
  selected_region_count integer,
  matched_feature_count integer,
  selected_feature_count integer,
  coverage_class text,
  matched_regions text[],
  match_basis jsonb,
  object_metadata jsonb
)
language sql
security invoker
stable
set search_path=''
as $function$
with q as (
  select * from intelligence.body_map_query_dimensions_v1(p_query)
),
counts as (
  select
    count(distinct region_key)::integer selected_region_count,
    count(*) filter(where dimension_key not in ('body_region','laterality','body_region_side'))::integer selected_feature_count
  from q
),
matches as (
  select
    vi.object_type,vi.object_id,vi.display_label,vi.object_kind,vi.source_domain,
    vi.source_jurisdiction,vi.framework_key,vi.framework_name,vi.source_status,
    vi.definition_text,vi.metadata object_metadata,
    q.selection_no,q.region_key query_region_key,q.side query_side,
    q.dimension_key query_dimension_key,q.dimension_value query_dimension_value,
    q.normalized_value query_normalized_value,
    dm.dimension_key matched_dimension_key,dm.dimension_value matched_dimension_value,
    dm.normalized_value matched_normalized_value,dm.relation_type,dm.source_basis,
    dm.confidence,dm.status mapping_status,dm.scope_region_key,dm.scope_side,
    dm.metadata mapping_metadata,
    case when q.dimension_key='body_region' then (
      select min(h.depth)
      from intelligence.v_body_region_hierarchy_v1 h
      where h.ancestor_region_key=q.normalized_value
        and h.descendant_region_key=dm.normalized_value
    ) else null end region_depth
  from q
  join intelligence.v_universal_vocabulary_dimension_map_v2 dm
    on (
      q.dimension_key='body_region'
      and dm.dimension_key='body_region'
      and exists(
        select 1
        from intelligence.v_body_region_hierarchy_v1 h
        where h.ancestor_region_key=q.normalized_value
          and h.descendant_region_key=dm.normalized_value
      )
    )
    or (
      q.dimension_key<>'body_region'
      and dm.dimension_key=q.dimension_key
      and dm.normalized_value=q.normalized_value
      and (
        dm.scope_region_key is null
        or exists(
          select 1
          from intelligence.v_body_region_hierarchy_v1 h
          where h.ancestor_region_key=q.region_key
            and h.descendant_region_key=dm.scope_region_key
        )
      )
      and (
        dm.scope_side is null
        or dm.scope_side='unspecified'
        or q.side=dm.scope_side
        or (dm.scope_side='bilateral' and q.side='bilateral')
      )
    )
  join intelligence.v_universal_vocabulary_index_v1 vi
    on vi.object_type=dm.object_type
   and vi.object_id=dm.object_id
),
agg as (
  select
    m.object_type,m.object_id,m.display_label,m.object_kind,m.source_domain,
    m.source_jurisdiction,m.framework_key,m.framework_name,m.source_status,
    m.definition_text,
    count(distinct m.query_region_key)
      filter(where m.query_dimension_key='body_region')::integer matched_region_count,
    count(distinct (m.selection_no,m.query_dimension_key,m.query_normalized_value))
      filter(where m.query_dimension_key not in ('body_region','laterality','body_region_side'))::integer matched_feature_count,
    array_agg(distinct m.query_region_key order by m.query_region_key)
      filter(where m.query_dimension_key='body_region') matched_regions,
    jsonb_agg(distinct jsonb_build_object(
      'selection_no',m.selection_no,
      'query_region',m.query_region_key,
      'query_side',m.query_side,
      'query_dimension',m.query_dimension_key,
      'query_value',m.query_dimension_value,
      'matched_dimension',m.matched_dimension_key,
      'matched_value',m.matched_dimension_value,
      'relation_type',m.relation_type,
      'source_basis',m.source_basis,
      'mapping_status',m.mapping_status,
      'confidence',m.confidence,
      'scope_region_key',m.scope_region_key,
      'scope_side',m.scope_side,
      'region_depth',m.region_depth,
      'mapping_metadata',m.mapping_metadata
    )) match_basis,
    m.object_metadata
  from matches m
  group by
    m.object_type,m.object_id,m.display_label,m.object_kind,m.source_domain,
    m.source_jurisdiction,m.framework_key,m.framework_name,m.source_status,
    m.definition_text,m.object_metadata
)
select
  a.object_type,a.object_id,a.display_label,a.object_kind,a.source_domain,
  a.source_jurisdiction,a.framework_key,a.framework_name,a.source_status,
  a.definition_text,a.matched_region_count,c.selected_region_count,
  a.matched_feature_count,c.selected_feature_count,
  case
    when a.matched_region_count>=2 then 'cross_region'
    when a.matched_region_count=1 and a.matched_feature_count>0 then 'region_plus_feature'
    when a.matched_region_count=1 then 'single_region'
    else 'feature_only'
  end coverage_class,
  coalesce(a.matched_regions,array[]::text[]),
  a.match_basis,
  a.object_metadata
from agg a
cross join counts c
order by
  a.matched_region_count desc,
  a.matched_feature_count desc,
  a.source_jurisdiction,
  a.display_label
limit greatest(1,least(coalesce(p_limit,100),500));
$function$;

comment on function intelligence.search_body_map_vocabulary_v2(jsonb,integer) is
'Region-aware cross-domain vocabulary retrieval. A feature attached to one selected body region cannot satisfy an object explicitly scoped to another region or side. Results express query coverage, not probability or diagnosis.';

create or replace view intelligence.v_body_map_query_choice_catalog_v1
with (security_invoker=true)
as
select
  'body_region'::text dimension_key,
  br.region_key::text value_key,
  br.region_name::text display_label,
  br.notes::text neutral_definition,
  'active'::text status,
  jsonb_build_object(
    'parent_region_key',br.parent_region_key,
    'laterality_allowed',br.laterality_allowed,
    'source','practice.body_regions'
  ) metadata
from practice.body_regions br
union all
select
  v.dimension_key,v.value_key,v.display_label,v.neutral_definition,v.status,
  v.metadata || jsonb_build_object('source','draft.reality_query_value_registry')
from draft.reality_query_value_registry v;

comment on view intelligence.v_body_map_query_choice_catalog_v1 is
'Neutral selectable vocabulary for the body-map UI. Choice availability is not a claim that any downstream framework, diagnosis, or treatment is correct.';

create or replace view intelligence.v_body_map_vocabulary_coverage_v2
with (security_invoker=true)
as
with mapped as (
  select
    dm.dimension_key,dm.normalized_value value_key,dm.dimension_value,
    vi.object_type,vi.object_id,vi.source_jurisdiction,vi.framework_key,
    coalesce(vi.framework_key,vi.source_jurisdiction) retrieval_lane_key
  from intelligence.v_universal_vocabulary_dimension_map_v2 dm
  join intelligence.v_universal_vocabulary_index_v1 vi
    on vi.object_type=dm.object_type and vi.object_id=dm.object_id
),
lane_counts as (
  select dimension_key,value_key,retrieval_lane_key,count(distinct (object_type,object_id))::bigint n
  from mapped
  group by dimension_key,value_key,retrieval_lane_key
)
select
  m.dimension_key,m.value_key,min(m.dimension_value) example_value,
  count(distinct (m.object_type,m.object_id))::bigint vocabulary_object_count,
  count(distinct m.source_jurisdiction)::bigint storage_jurisdiction_count,
  count(distinct m.framework_key) filter(where m.framework_key is not null)::bigint framework_count,
  count(distinct m.retrieval_lane_key)::bigint retrieval_lane_count,
  jsonb_object_agg(l.retrieval_lane_key,l.n order by l.retrieval_lane_key) objects_by_retrieval_lane
from mapped m
join lane_counts l
  on l.dimension_key=m.dimension_key
 and l.value_key=m.value_key
 and l.retrieval_lane_key=m.retrieval_lane_key
group by m.dimension_key,m.value_key;

comment on view intelligence.v_body_map_vocabulary_coverage_v2 is
'Coverage audit using independent retrieval lanes. Framework-native rows are counted by framework_key rather than collapsed into one storage jurisdiction.';

create or replace view intelligence.v_body_map_query_value_gap_queue_v2
with (security_invoker=true)
as
select
  c.dimension_key,c.value_key,c.display_label,c.neutral_definition,
  c.status choice_status,
  coalesce(v.vocabulary_object_count,0)::bigint vocabulary_object_count,
  coalesce(v.retrieval_lane_count,0)::bigint retrieval_lane_count,
  coalesce(v.framework_count,0)::bigint framework_count,
  case
    when coalesce(v.vocabulary_object_count,0)=0 then 'unmapped'
    when coalesce(v.retrieval_lane_count,0)=1 then 'single_lane'
    else 'cross_lane'
  end coverage_state,
  case
    when coalesce(v.vocabulary_object_count,0)=0
      then 'research source-native vocabulary and add evidence-custodied descriptors'
    when coalesce(v.retrieval_lane_count,0)=1
      then 'expand to independent source traditions without rewriting existing mappings'
    else 'review provenance, scope, and relationship precision before UI release'
  end allowed_next_move,
  coalesce(v.objects_by_retrieval_lane,'{}'::jsonb) objects_by_retrieval_lane
from intelligence.v_body_map_query_choice_catalog_v1 c
left join intelligence.v_body_map_vocabulary_coverage_v2 v
  on v.dimension_key=c.dimension_key
 and v.value_key=lower(regexp_replace(trim(c.value_key),'\s+','_','g'));

comment on view intelligence.v_body_map_query_value_gap_queue_v2 is
'Query-vocabulary coverage queue measured across independent source/framework lanes rather than merely schema/storage jurisdictions.';

-- Remove superseded pre-scope search objects if an earlier exploratory build existed.
drop view if exists intelligence.v_body_map_query_value_gap_queue_v1;
drop view if exists intelligence.v_body_map_vocabulary_coverage_v1;
drop function if exists intelligence.search_body_map_vocabulary_v1(jsonb,integer);
drop view if exists intelligence.v_universal_vocabulary_dimension_map_v1;

revoke all on intelligence.v_body_region_hierarchy_v1 from anon, authenticated;
revoke all on intelligence.v_universal_vocabulary_index_v1 from anon, authenticated;
revoke all on intelligence.v_universal_vocabulary_dimension_map_v2 from anon, authenticated;
revoke all on intelligence.v_body_map_query_choice_catalog_v1 from anon, authenticated;
revoke all on intelligence.v_body_map_vocabulary_coverage_v2 from anon, authenticated;
revoke all on intelligence.v_body_map_query_value_gap_queue_v2 from anon, authenticated;

revoke all on function intelligence.body_map_query_dimensions_v1(jsonb) from public,anon,authenticated;
revoke all on function intelligence.search_body_map_vocabulary_v2(jsonb,integer) from public,anon,authenticated;
grant execute on function intelligence.body_map_query_dimensions_v1(jsonb) to service_role;
grant execute on function intelligence.search_body_map_vocabulary_v2(jsonb,integer) to service_role;

commit;
