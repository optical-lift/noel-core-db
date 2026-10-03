create index if not exists reality_relationship_topology_semantics_axis_idx
  on reality.relationship_topology_semantics (topology_axis)
  where topology_axis is not null;

create index if not exists reality_relationship_topology_semantics_presence_class_idx
  on reality.relationship_topology_semantics (default_presence_class)
  where default_presence_class is not null;
