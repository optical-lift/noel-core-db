create table if not exists titus.canon_structures (
  canon_structure_id uuid primary key default gen_random_uuid(),
  program_id uuid null references titus.programs(program_id),
  structure_key text not null unique,
  structure_name text not null,
  structure_type text not null check (structure_type = any (array['architecture','taxonomy','contrast','sequence','diagnostic_map','jurisdiction_map','other']::text[])),
  structure_summary text not null,
  status text not null default 'candidate' check (status = any (array['candidate','reviewed','approved','superseded','retired']::text[])),
  confidence text null check (confidence is null or confidence = any (array['low','medium','high']::text[])),
  version integer not null default 1 check (version > 0),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists titus.canon_structure_nodes (
  canon_structure_node_id uuid primary key default gen_random_uuid(),
  canon_structure_id uuid not null references titus.canon_structures(canon_structure_id) on delete cascade,
  node_key text not null,
  node_label text not null,
  node_kind text not null check (node_kind = any (array['source','function','operation','carrier','state','condition','decision','evidence','outcome','boundary','case','speech_act','principle','other']::text[])),
  node_description text null,
  canon_claim_id uuid null references titus.canon_claims(canon_claim_id),
  truth_ref_id uuid null references titus.truth_refs(truth_ref_id),
  sort_order integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status = any (array['active','retired']::text[])),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (canon_structure_id, node_key)
);

create table if not exists titus.canon_structure_edges (
  canon_structure_edge_id uuid primary key default gen_random_uuid(),
  canon_structure_id uuid not null references titus.canon_structures(canon_structure_id) on delete cascade,
  from_node_id uuid not null references titus.canon_structure_nodes(canon_structure_node_id) on delete cascade,
  to_node_id uuid not null references titus.canon_structure_nodes(canon_structure_node_id) on delete cascade,
  edge_type text not null check (edge_type = any (array['governs','authorizes','carries','mediates','enables','tests','receives','resists','forms','coordinates','produces','reveals','contrasts_with','distinguishes_from','depends_on','can_fail_at','bounded_by','classifies_as','supports','other']::text[])),
  edge_label text null,
  edge_description text null,
  canon_claim_id uuid null references titus.canon_claims(canon_claim_id),
  truth_ref_id uuid null references titus.truth_refs(truth_ref_id),
  sort_order integer not null default 0,
  confidence text null check (confidence is null or confidence = any (array['low','medium','high']::text[])),
  status text not null default 'active' check (status = any (array['active','retired']::text[])),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (canon_structure_id, from_node_id, to_node_id, edge_type),
  check (from_node_id <> to_node_id)
);

create table if not exists titus.lesson_structure_links (
  lesson_structure_link_id uuid primary key default gen_random_uuid(),
  lesson_slug text not null references titus.lesson_packets(lesson_slug) on delete cascade,
  canon_structure_id uuid not null references titus.canon_structures(canon_structure_id) on delete cascade,
  lesson_role text not null check (lesson_role = any (array['primary_architecture','taxonomy','contrast','diagnostic','application','supporting','other']::text[])),
  teaching_purpose text null,
  sort_order integer not null default 0,
  status text not null default 'candidate' check (status = any (array['candidate','approved','rejected','retired']::text[])),
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_slug, canon_structure_id, lesson_role)
);

create index if not exists canon_structure_nodes_structure_idx on titus.canon_structure_nodes(canon_structure_id, sort_order);
create index if not exists canon_structure_nodes_claim_idx on titus.canon_structure_nodes(canon_claim_id) where canon_claim_id is not null;
create index if not exists canon_structure_nodes_truth_ref_idx on titus.canon_structure_nodes(truth_ref_id) where truth_ref_id is not null;
create index if not exists canon_structure_edges_structure_idx on titus.canon_structure_edges(canon_structure_id, sort_order);
create index if not exists canon_structure_edges_from_idx on titus.canon_structure_edges(from_node_id);
create index if not exists canon_structure_edges_to_idx on titus.canon_structure_edges(to_node_id);
create index if not exists canon_structure_edges_claim_idx on titus.canon_structure_edges(canon_claim_id) where canon_claim_id is not null;
create index if not exists lesson_structure_links_lesson_idx on titus.lesson_structure_links(lesson_slug, sort_order);

alter table titus.canon_structures enable row level security;
alter table titus.canon_structure_nodes enable row level security;
alter table titus.canon_structure_edges enable row level security;
alter table titus.lesson_structure_links enable row level security;

revoke all on table titus.canon_structures from anon, authenticated;
revoke all on table titus.canon_structure_nodes from anon, authenticated;
revoke all on table titus.canon_structure_edges from anon, authenticated;
revoke all on table titus.lesson_structure_links from anon, authenticated;

create or replace view titus.v_canon_structure_graph as
select
  s.canon_structure_id,
  s.structure_key,
  s.structure_name,
  s.structure_type,
  s.status as structure_status,
  s.confidence as structure_confidence,
  n1.node_key as from_node_key,
  n1.node_label as from_node_label,
  e.edge_type,
  e.edge_label,
  e.edge_description,
  n2.node_key as to_node_key,
  n2.node_label as to_node_label,
  cc.claim_key as governing_claim_key,
  cc.claim_text as governing_claim_text,
  e.confidence as edge_confidence,
  e.sort_order
from titus.canon_structures s
join titus.canon_structure_edges e on e.canon_structure_id=s.canon_structure_id and e.status='active'
join titus.canon_structure_nodes n1 on n1.canon_structure_node_id=e.from_node_id and n1.status='active'
join titus.canon_structure_nodes n2 on n2.canon_structure_node_id=e.to_node_id and n2.status='active'
left join titus.canon_claims cc on cc.canon_claim_id=e.canon_claim_id;

comment on table titus.canon_structures is 'Reusable canonical teaching structures. These are project teaching architecture, not duplicate Noel/Song truth objects.';
comment on table titus.canon_structure_nodes is 'Addressable nodes within a reusable canonical structure. Nodes may point to a canon claim or truth ref without copying Noel/Song definitions.';
comment on table titus.canon_structure_edges is 'Directed semantic relations between structure nodes, optionally governed by a reusable canon claim or truth ref.';
comment on table titus.lesson_structure_links is 'Links lesson packets to reusable canonical structures with a lesson-specific teaching role.';