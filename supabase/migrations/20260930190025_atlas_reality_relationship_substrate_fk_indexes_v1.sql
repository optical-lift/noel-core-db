create index if not exists reality_relationship_kinds_inverse_idx
  on reality.relationship_kinds (inverse_relationship_kind)
  where inverse_relationship_kind is not null;

create index if not exists reality_relationship_adjudications_principal_idx
  on reality.relationship_proposition_adjudications (adjudicated_by_principal_id)
  where adjudicated_by_principal_id is not null;
