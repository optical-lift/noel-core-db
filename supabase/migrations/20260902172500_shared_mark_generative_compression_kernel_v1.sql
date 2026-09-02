begin;

-- Mark Generative Compression Kernel v1.
--
-- Purpose: test whether blind physical information structures admit a smaller
-- shared generative vocabulary than matched controls. This is an analysis layer,
-- not a semantic layer. No culture, language, reading, sign name, conventional
-- meaning, chronology, geography, or historical system identity is admitted.
--
-- The primary score is minimum-description-length-like and pays for:
--   1. the learned grammar/codebook,
--   2. the encoded program for every evaluated graph,
--   3. any residual graph needed for exact reconstruction.
-- A claimed compression result is authoritative only when every member of the
-- evaluated corpus is exactly reconstructed.

create table mark.compression_codec_registry (
  codec_key text primary key,
  codec_name text not null,
  objective text not null,
  cost_unit text not null default 'bits',
  structural_definition text not null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(codec_key) <> ''),
  check (btrim(codec_name) <> ''),
  check (objective in ('minimum_description_length')),
  check (cost_unit='bits')
);

insert into mark.compression_codec_registry(
  codec_key,codec_name,objective,structural_definition
)
values (
  'MDL_JSON_GRAPH_V1',
  'Canonical graph minimum description length v1',
  'minimum_description_length',
  'Costs are UTF-8 serialized byte length multiplied by eight. Raw cost is the canonical blind graph snapshot. Grammar cost is the serialized anonymous rule key plus its pattern graph. Program cost is the serialized rule-invocation program. Residual cost is any remaining blind graph required for exact reconstruction. Standalone score charges grammar once; transfer score reports program plus residual after a grammar has been learned independently.'
)
on conflict (codec_key) do nothing;

create table mark.compression_representation_registry (
  representation_key text primary key,
  representation_name text not null,
  structural_definition text not null,
  includes_morphology boolean not null default false,
  includes_material_channel boolean not null default false,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(representation_key) <> ''),
  check (btrim(representation_name) <> '')
);

insert into mark.compression_representation_registry(
  representation_key,representation_name,structural_definition,includes_morphology,includes_material_channel
)
values
  (
    'REP_TOPOLOGY_ONLY_V1',
    'Anonymous topology graph v1',
    'Anonymous component nodes grouped only by blind unit membership plus directed physical-relation edges. Morphology, material channel, geometry, source identity, and historical context are excluded.',
    false,false
  ),
  (
    'REP_TOPOLOGY_MORPHOLOGY_V1',
    'Anonymous topology plus morphology graph v1',
    'Anonymous component nodes grouped by blind unit membership and carrying only the highest-confidence blind physical morphology, plus directed physical-relation edges. Material channel, geometry, source identity, and historical context are excluded.',
    true,false
  )
on conflict (representation_key) do nothing;

create table mark.compression_units (
  compression_unit_id bigint generated always as identity primary key,
  unit_key text not null unique,
  unit_scope text not null,
  selection_basis text not null,
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(unit_key) <> ''),
  check (unit_scope in ('single_instance','source_object_graph','sequence_window','custom_blind_subgraph')),
  check (selection_basis in ('physical_boundary','sequence_window','blind_custom')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.compression_unit_members (
  compression_unit_member_id bigint generated always as identity primary key,
  compression_unit_id bigint not null references mark.compression_units(compression_unit_id),
  instance_id bigint not null references mark.instances(instance_id),
  member_order integer not null,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(compression_unit_id,instance_id),
  unique(compression_unit_id,member_order),
  check (member_order >= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_unit_members_instance_idx
  on mark.compression_unit_members(instance_id);

create or replace function mark.graph_payload_is_valid_v1(
  p_graph jsonb,
  p_representation_key text
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, mark
as $$
declare
  elem jsonb;
  k text;
  allowed_node_keys text[];
begin
  if p_graph is null or jsonb_typeof(p_graph) <> 'object' then
    return false;
  end if;

  if p_representation_key not in ('REP_TOPOLOGY_ONLY_V1','REP_TOPOLOGY_MORPHOLOGY_V1') then
    return false;
  end if;

  if p_graph->>'representation' is distinct from p_representation_key then
    return false;
  end if;

  if not (p_graph ?& array['representation','members','nodes','edges']) then
    return false;
  end if;

  for k in select jsonb_object_keys(p_graph) loop
    if k not in ('representation','members','nodes','edges') then
      return false;
    end if;
  end loop;

  if jsonb_typeof(p_graph->'members') <> 'array'
     or jsonb_typeof(p_graph->'nodes') <> 'array'
     or jsonb_typeof(p_graph->'edges') <> 'array' then
    return false;
  end if;

  for elem in select value from jsonb_array_elements(p_graph->'members') loop
    if jsonb_typeof(elem) <> 'object'
       or not (elem ?& array['member','component_count']) then
      return false;
    end if;
    for k in select jsonb_object_keys(elem) loop
      if k not in ('member','component_count') then return false; end if;
    end loop;
    if coalesce(elem->>'member','') !~ '^[0-9]+$'
       or coalesce(elem->>'component_count','') !~ '^[0-9]+$' then
      return false;
    end if;
  end loop;

  if p_representation_key='REP_TOPOLOGY_MORPHOLOGY_V1' then
    allowed_node_keys := array['id','member','morphology'];
  else
    allowed_node_keys := array['id','member'];
  end if;

  for elem in select value from jsonb_array_elements(p_graph->'nodes') loop
    if jsonb_typeof(elem) <> 'object'
       or not (elem ?& array['id','member']) then
      return false;
    end if;
    if p_representation_key='REP_TOPOLOGY_MORPHOLOGY_V1'
       and not (elem ? 'morphology') then
      return false;
    end if;
    for k in select jsonb_object_keys(elem) loop
      if not (k=any(allowed_node_keys)) then return false; end if;
    end loop;
    if coalesce(elem->>'id','') !~ '^[0-9]+$'
       or coalesce(elem->>'member','') !~ '^[0-9]+$' then
      return false;
    end if;
    if p_representation_key='REP_TOPOLOGY_MORPHOLOGY_V1'
       and btrim(coalesce(elem->>'morphology',''))='' then
      return false;
    end if;
  end loop;

  for elem in select value from jsonb_array_elements(p_graph->'edges') loop
    if jsonb_typeof(elem) <> 'object'
       or not (elem ?& array['from','relation','to']) then
      return false;
    end if;
    for k in select jsonb_object_keys(elem) loop
      if k not in ('from','relation','to') then return false; end if;
    end loop;
    if coalesce(elem->>'from','') !~ '^[0-9]+$'
       or coalesce(elem->>'to','') !~ '^[0-9]+$'
       or btrim(coalesce(elem->>'relation',''))='' then
      return false;
    end if;
  end loop;

  return true;
end
$$;

create or replace function mark.canonical_compression_unit_v1(
  p_compression_unit_id bigint,
  p_representation_key text
)
returns jsonb
language sql
stable
set search_path = pg_catalog, mark
as $$
with member_rows as (
  select um.instance_id,um.member_order
  from mark.compression_unit_members um
  where um.compression_unit_id=p_compression_unit_id
),
node_source as (
  select
    c.component_id,
    m.member_order,
    c.component_order,
    coalesce((
      select cm.morphology_key
      from mark.component_morphologies cm
      where cm.component_id=c.component_id
      order by cm.confidence desc,cm.morphology_key
      limit 1
    ),'M_UNSPECIFIED') as morphology_key
  from member_rows m
  join mark.components c on c.instance_id=m.instance_id
),
node_map as (
  select
    ns.*,
    row_number() over (
      order by ns.member_order,ns.component_order nulls last,ns.component_id
    )::bigint as local_id
  from node_source ns
),
member_payload as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'member',m.member_order,
        'component_count',(select count(*) from node_source ns where ns.member_order=m.member_order)
      ) order by m.member_order
    ),'[]'::jsonb
  ) as payload
  from member_rows m
),
node_payload as (
  select coalesce(
    jsonb_agg(
      case
        when p_representation_key='REP_TOPOLOGY_MORPHOLOGY_V1' then
          jsonb_build_object('id',n.local_id,'member',n.member_order,'morphology',n.morphology_key)
        else
          jsonb_build_object('id',n.local_id,'member',n.member_order)
      end
      order by n.local_id
    ),'[]'::jsonb
  ) as payload
  from node_map n
),
edge_payload as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object('from',s.local_id,'relation',cr.relation_key,'to',o.local_id)
      order by s.local_id,cr.relation_key,o.local_id,cr.component_relation_id
    ),'[]'::jsonb
  ) as payload
  from mark.component_relations cr
  join node_map s on s.component_id=cr.subject_component_id
  join node_map o on o.component_id=cr.object_component_id
)
select jsonb_build_object(
  'representation',p_representation_key,
  'members',(select payload from member_payload),
  'nodes',(select payload from node_payload),
  'edges',(select payload from edge_payload)
)
where exists (
  select 1
  from mark.compression_representation_registry rr
  where rr.representation_key=p_representation_key
    and rr.strict_blind_allowed
);
$$;

create table mark.compression_corpora (
  compression_corpus_id bigint generated always as identity primary key,
  corpus_key text not null unique,
  representation_key text not null references mark.compression_representation_registry(representation_key),
  corpus_kind text not null,
  control_method text null,
  source_corpus_id bigint null references mark.compression_corpora(compression_corpus_id),
  random_seed bigint null,
  generated_by_run_id bigint null references instrument.runs(instrument_run_id),
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(corpus_key) <> ''),
  check (corpus_kind in ('evidence','control')),
  check (control_method is null or control_method in (
    'relation_shuffle','degree_preserving_shuffle','component_count_matched_synthetic',
    'morphology_frequency_matched_synthetic','random_graph_matched_complexity'
  )),
  check (
    (corpus_kind='evidence' and control_method is null and source_corpus_id is null)
    or
    (corpus_kind='control' and control_method is not null and source_corpus_id is not null)
  ),
  check (source_corpus_id is null or source_corpus_id <> compression_corpus_id),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_corpora_source_idx
  on mark.compression_corpora(source_corpus_id);

create table mark.compression_corpus_members (
  compression_corpus_member_id bigint generated always as identity primary key,
  compression_corpus_id bigint not null references mark.compression_corpora(compression_corpus_id),
  member_key text not null,
  source_unit_id bigint null references mark.compression_units(compression_unit_id),
  graph_snapshot jsonb not null,
  graph_hash text generated always as (
    encode(extensions.digest(graph_snapshot::text,'sha256'),'hex')
  ) stored,
  raw_cost_bits bigint generated always as (
    octet_length(graph_snapshot::text)::bigint * 8
  ) stored,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(compression_corpus_id,member_key),
  unique(compression_corpus_id,source_unit_id),
  check (btrim(member_key) <> ''),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_corpus_members_source_unit_idx
  on mark.compression_corpus_members(source_unit_id);

create or replace function mark.validate_compression_corpus_member_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  k text;
  rep text;
  expected jsonb;
begin
  select corpus_kind,representation_key into k,rep
  from mark.compression_corpora
  where compression_corpus_id=new.compression_corpus_id;

  if k is null then
    raise exception 'MARK_COMPRESSION_CORPUS_MEMBER_REJECTED: unknown corpus';
  end if;

  if not mark.graph_payload_is_valid_v1(new.graph_snapshot,rep) then
    raise exception 'MARK_COMPRESSION_GRAPH_REJECTED: graph payload violates blind representation %',rep;
  end if;

  if k='evidence' then
    if new.source_unit_id is null then
      raise exception 'MARK_COMPRESSION_EVIDENCE_MEMBER_REJECTED: evidence member requires source unit';
    end if;
    expected := mark.canonical_compression_unit_v1(new.source_unit_id,rep);
    if expected is null or new.graph_snapshot is distinct from expected then
      raise exception 'MARK_COMPRESSION_EVIDENCE_MEMBER_REJECTED: graph snapshot is not canonical source-unit graph';
    end if;
  elsif new.source_unit_id is not null then
    raise exception 'MARK_COMPRESSION_CONTROL_MEMBER_REJECTED: control member cannot point to evidence unit';
  end if;

  return new;
end
$$;

create trigger validate_compression_corpus_member_v1
before insert or update on mark.compression_corpus_members
for each row execute function mark.validate_compression_corpus_member_v1();

create table mark.compression_models (
  compression_model_id bigint generated always as identity primary key,
  model_key text not null unique,
  codec_key text not null references mark.compression_codec_registry(codec_key),
  representation_key text not null references mark.compression_representation_registry(representation_key),
  training_corpus_id bigint not null references mark.compression_corpora(compression_corpus_id),
  random_seed bigint null,
  learned_by_run_id bigint null references instrument.runs(instrument_run_id),
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(model_key) <> ''),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_models_training_corpus_idx
  on mark.compression_models(training_corpus_id);

create or replace function mark.validate_compression_model_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  corpus_rep text;
begin
  select representation_key into corpus_rep
  from mark.compression_corpora
  where compression_corpus_id=new.training_corpus_id;

  if corpus_rep is distinct from new.representation_key then
    raise exception 'MARK_COMPRESSION_MODEL_REJECTED: training corpus representation mismatch';
  end if;

  return new;
end
$$;

create trigger validate_compression_model_v1
before insert or update on mark.compression_models
for each row execute function mark.validate_compression_model_v1();

create table mark.compression_rules (
  compression_rule_id bigint generated always as identity primary key,
  compression_model_id bigint not null references mark.compression_models(compression_model_id),
  rule_key text not null,
  rule_kind text not null default 'macro',
  pattern_graph jsonb not null,
  definition_cost_bits bigint generated always as (
    octet_length(rule_key || '=' || pattern_graph::text)::bigint * 8
  ) stored,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(compression_model_id,rule_key),
  check (rule_key ~ '^R[0-9]{4,}$'),
  check (rule_kind in ('primitive','composition','macro')),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_rules_model_idx
  on mark.compression_rules(compression_model_id);

create or replace function mark.validate_compression_rule_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  rep text;
begin
  select representation_key into rep
  from mark.compression_models
  where compression_model_id=new.compression_model_id;

  if rep is null or not mark.graph_payload_is_valid_v1(new.pattern_graph,rep) then
    raise exception 'MARK_COMPRESSION_RULE_REJECTED: pattern is not a blind graph in model representation';
  end if;

  return new;
end
$$;

create trigger validate_compression_rule_v1
before insert or update on mark.compression_rules
for each row execute function mark.validate_compression_rule_v1();

create table mark.compression_encodings (
  compression_encoding_id bigint generated always as identity primary key,
  compression_model_id bigint not null references mark.compression_models(compression_model_id),
  compression_corpus_member_id bigint not null references mark.compression_corpus_members(compression_corpus_member_id),
  encoded_program jsonb null,
  residual_graph jsonb null,
  encoding_cost_bits bigint generated always as (
    case when encoded_program is null then 0 else octet_length(encoded_program::text)::bigint * 8 end
  ) stored,
  residual_cost_bits bigint generated always as (
    case when residual_graph is null then 0 else octet_length(residual_graph::text)::bigint * 8 end
  ) stored,
  reconstructed_graph_hash text not null,
  reconstruction_exact boolean not null default false,
  encoded_by_run_id bigint null references instrument.runs(instrument_run_id),
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(compression_model_id,compression_corpus_member_id),
  check (reconstructed_graph_hash ~ '^[0-9a-f]{64}$'),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index compression_encodings_member_idx
  on mark.compression_encodings(compression_corpus_member_id);

create or replace function mark.validate_compression_encoding_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  model_rep text;
  corpus_rep text;
  expected_hash text;
  step jsonb;
  k text;
  rk text;
begin
  select m.representation_key into model_rep
  from mark.compression_models m
  where m.compression_model_id=new.compression_model_id;

  select c.representation_key,cm.graph_hash into corpus_rep,expected_hash
  from mark.compression_corpus_members cm
  join mark.compression_corpora c on c.compression_corpus_id=cm.compression_corpus_id
  where cm.compression_corpus_member_id=new.compression_corpus_member_id;

  if model_rep is null or corpus_rep is null or model_rep is distinct from corpus_rep then
    raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: model/member representation mismatch';
  end if;

  if new.residual_graph is not null
     and not mark.graph_payload_is_valid_v1(new.residual_graph,model_rep) then
    raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: residual is not a blind graph';
  end if;

  if new.encoded_program is not null then
    if jsonb_typeof(new.encoded_program) <> 'array' then
      raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: encoded_program must be an array';
    end if;

    for step in select value from jsonb_array_elements(new.encoded_program) loop
      if jsonb_typeof(step) <> 'object' or not (step ? 'rule') then
        raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: every program step requires rule';
      end if;
      for k in select jsonb_object_keys(step) loop
        if k not in ('rule','anchor_member','anchor_node','repeat') then
          raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: program field % is not blind-grammar authority',k;
        end if;
      end loop;
      rk := step->>'rule';
      if rk !~ '^R[0-9]{4,}$' or not exists (
        select 1 from mark.compression_rules r
        where r.compression_model_id=new.compression_model_id
          and r.rule_key=rk
      ) then
        raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: unknown model rule %',rk;
      end if;
      if step ? 'anchor_member' and coalesce(step->>'anchor_member','') !~ '^[0-9]+$' then
        raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: anchor_member must be a positive integer';
      end if;
      if step ? 'anchor_node' and coalesce(step->>'anchor_node','') !~ '^[0-9]+$' then
        raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: anchor_node must be a positive integer';
      end if;
      if step ? 'repeat' and (
        coalesce(step->>'repeat','') !~ '^[0-9]+$' or (step->>'repeat')::bigint < 1
      ) then
        raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: repeat must be a positive integer';
      end if;
    end loop;
  end if;

  new.reconstruction_exact := new.reconstructed_graph_hash = expected_hash;

  if new.record_status in ('reviewed','frozen') and not new.reconstruction_exact then
    raise exception 'MARK_COMPRESSION_ENCODING_REJECTED: reviewed/frozen encoding must exactly reconstruct corpus member';
  end if;

  return new;
end
$$;

create trigger validate_compression_encoding_v1
before insert or update on mark.compression_encodings
for each row execute function mark.validate_compression_encoding_v1();

create view mark.blind_compression_scores_v1
with (security_invoker = true)
as
with grammar as (
  select
    m.compression_model_id,
    coalesce(sum(r.definition_cost_bits) filter (where r.record_status in ('reviewed','frozen')),0)::bigint as grammar_cost_bits,
    count(r.compression_rule_id) filter (where r.record_status in ('reviewed','frozen'))::bigint as rule_count
  from mark.compression_models m
  left join mark.compression_rules r on r.compression_model_id=m.compression_model_id
  group by m.compression_model_id
),
corpus_totals as (
  select
    c.compression_corpus_id,
    count(cm.compression_corpus_member_id) filter (where cm.record_status in ('reviewed','frozen'))::bigint as corpus_member_count
  from mark.compression_corpora c
  left join mark.compression_corpus_members cm on cm.compression_corpus_id=c.compression_corpus_id
  group by c.compression_corpus_id
),
encoded as (
  select
    e.compression_model_id,
    cm.compression_corpus_id,
    count(*)::bigint as encoded_member_count,
    sum(cm.raw_cost_bits)::bigint as raw_cost_bits,
    sum(e.encoding_cost_bits)::bigint as program_cost_bits,
    sum(e.residual_cost_bits)::bigint as residual_cost_bits,
    count(*) filter (where e.reconstruction_exact)::bigint as exact_member_count
  from mark.compression_encodings e
  join mark.compression_corpus_members cm
    on cm.compression_corpus_member_id=e.compression_corpus_member_id
  where e.record_status in ('reviewed','frozen')
    and cm.record_status in ('reviewed','frozen')
  group by e.compression_model_id,cm.compression_corpus_id
)
select
  e.compression_model_id,
  e.compression_corpus_id,
  m.training_corpus_id,
  c.corpus_kind,
  c.control_method,
  ct.corpus_member_count,
  e.encoded_member_count,
  case when ct.corpus_member_count=0 then 0::numeric
       else e.encoded_member_count::numeric/ct.corpus_member_count::numeric end as coverage_fraction,
  e.exact_member_count,
  e.raw_cost_bits,
  g.grammar_cost_bits,
  g.rule_count,
  e.program_cost_bits,
  e.residual_cost_bits,
  (g.grammar_cost_bits + e.program_cost_bits + e.residual_cost_bits)::bigint as standalone_total_bits,
  (e.program_cost_bits + e.residual_cost_bits)::bigint as transfer_total_bits,
  case when e.raw_cost_bits=0 then null
       else (g.grammar_cost_bits + e.program_cost_bits + e.residual_cost_bits)::numeric/e.raw_cost_bits::numeric end as standalone_ratio,
  case when e.raw_cost_bits=0 then null
       else (e.program_cost_bits + e.residual_cost_bits)::numeric/e.raw_cost_bits::numeric end as transfer_ratio
from encoded e
join mark.compression_models m on m.compression_model_id=e.compression_model_id
join mark.compression_corpora c on c.compression_corpus_id=e.compression_corpus_id
join corpus_totals ct on ct.compression_corpus_id=e.compression_corpus_id
join grammar g on g.compression_model_id=e.compression_model_id
where m.record_status in ('reviewed','frozen')
  and c.record_status in ('reviewed','frozen');

create view mark.blind_compression_complete_scores_v1
with (security_invoker = true)
as
select *
from mark.blind_compression_scores_v1
where coverage_fraction=1
  and exact_member_count=encoded_member_count;

create view mark.blind_compression_control_delta_v1
with (security_invoker = true)
as
select
  control_score.compression_model_id,
  evidence.compression_corpus_id as evidence_corpus_id,
  control.compression_corpus_id as control_corpus_id,
  control.control_method,
  evidence_score.standalone_ratio as evidence_standalone_ratio,
  control_score.standalone_ratio as control_standalone_ratio,
  control_score.standalone_ratio-evidence_score.standalone_ratio as control_minus_evidence_ratio,
  evidence_score.transfer_ratio as evidence_transfer_ratio,
  control_score.transfer_ratio as control_transfer_ratio,
  control_score.transfer_ratio-evidence_score.transfer_ratio as control_minus_evidence_transfer_ratio
from mark.compression_corpora control
join mark.compression_corpora evidence
  on evidence.compression_corpus_id=control.source_corpus_id
join mark.blind_compression_complete_scores_v1 control_score
  on control_score.compression_corpus_id=control.compression_corpus_id
join mark.blind_compression_complete_scores_v1 evidence_score
  on evidence_score.compression_corpus_id=evidence.compression_corpus_id
 and evidence_score.compression_model_id=control_score.compression_model_id
where control.corpus_kind='control';

create view mark.blind_compression_rule_reuse_v1
with (security_invoker = true)
as
select
  e.compression_model_id,
  step->>'rule' as rule_key,
  count(*)::bigint as invocation_count,
  count(distinct e.compression_corpus_member_id)::bigint as distinct_member_count,
  count(distinct cm.compression_corpus_id)::bigint as distinct_corpus_count
from mark.compression_encodings e
join mark.compression_corpus_members cm
  on cm.compression_corpus_member_id=e.compression_corpus_member_id
cross join lateral jsonb_array_elements(coalesce(e.encoded_program,'[]'::jsonb)) step
where e.record_status in ('reviewed','frozen')
group by e.compression_model_id,step->>'rule';

comment on table mark.compression_units is
  'Blind analysis units composed from one or more physical Mark instances. Unit membership carries no historical system identity.';
comment on table mark.compression_corpora is
  'Blind evidence or matched-control corpora for generative compression experiments.';
comment on table mark.compression_models is
  'Candidate blind generative grammars trained on a declared compression corpus.';
comment on table mark.compression_rules is
  'Anonymous reusable blind graph patterns. Rule identity carries no conventional meaning.';
comment on table mark.compression_encodings is
  'Rule programs plus residual blind graph sufficient to reconstruct an evaluated graph; reviewed/frozen rows must reconstruct exactly.';
comment on view mark.blind_compression_complete_scores_v1 is
  'Authoritative complete-corpus description-length scores. Lower ratios indicate shorter descriptions; all members must be exactly reconstructed.';
comment on view mark.blind_compression_control_delta_v1 is
  'Difference between real-evidence and matched-control compression ratios under the same blind model. Positive control-minus-evidence values mean the evidence compressed more efficiently.';

-- Freeze/correction behavior.
do $$
declare rel text;
begin
  foreach rel in array array[
    'compression_units','compression_unit_members','compression_corpora',
    'compression_corpus_members','compression_models','compression_rules','compression_encodings'
  ] loop
    execute format(
      'create trigger %I before update or delete on mark.%I for each row execute function mark.guard_frozen_row_v1()',
      'guard_frozen_' || rel || '_v1', rel
    );
    execute format(
      'create trigger %I before update on mark.%I for each row execute function mark.touch_updated_at_v1()',
      'touch_updated_' || rel || '_v1', rel
    );
  end loop;
end
$$;

alter table mark.record_supersessions
  drop constraint if exists record_supersessions_object_type_check;
alter table mark.record_supersessions
  add constraint record_supersessions_object_type_check
  check (object_type in (
    'source_object','surface','capture','capture_surface','capture_equivalence','region',
    'instance','component','component_relation','sequence_zone','sequence_member',
    'component_morphology','feature_observation','operator_observation',
    'contrast_pair','contrast_delta','contrast_transformation',
    'compression_unit','compression_unit_member','compression_corpus','compression_corpus_member',
    'compression_model','compression_rule','compression_encoding'
  ));

alter table mark.compression_codec_registry enable row level security;
alter table mark.compression_representation_registry enable row level security;
alter table mark.compression_units enable row level security;
alter table mark.compression_unit_members enable row level security;
alter table mark.compression_corpora enable row level security;
alter table mark.compression_corpus_members enable row level security;
alter table mark.compression_models enable row level security;
alter table mark.compression_rules enable row level security;
alter table mark.compression_encodings enable row level security;

revoke all on table
  mark.compression_codec_registry,
  mark.compression_representation_registry,
  mark.compression_units,
  mark.compression_unit_members,
  mark.compression_corpora,
  mark.compression_corpus_members,
  mark.compression_models,
  mark.compression_rules,
  mark.compression_encodings,
  mark.blind_compression_scores_v1,
  mark.blind_compression_complete_scores_v1,
  mark.blind_compression_control_delta_v1,
  mark.blind_compression_rule_reuse_v1
from public, anon, authenticated, service_role;

revoke all on function mark.graph_payload_is_valid_v1(jsonb,text)
from public, anon, authenticated, service_role;
revoke all on function mark.canonical_compression_unit_v1(bigint,text)
from public, anon, authenticated, service_role;
revoke all on function mark.validate_compression_corpus_member_v1()
from public, anon, authenticated, service_role;
revoke all on function mark.validate_compression_model_v1()
from public, anon, authenticated, service_role;
revoke all on function mark.validate_compression_rule_v1()
from public, anon, authenticated, service_role;
revoke all on function mark.validate_compression_encoding_v1()
from public, anon, authenticated, service_role;

-- Runtime roles must remain outside both compression evidence and context authority.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark_context','USAGE')
       or has_table_privilege(role_name,'mark.compression_models','SELECT')
       or has_table_privilege(role_name,'mark.blind_compression_complete_scores_v1','SELECT') then
      raise exception 'MARK_COMPRESSION_MEMBRANE_VIOLATION: runtime role % can reach generative compression authority',role_name;
    end if;
  end loop;
end
$$;

commit;
