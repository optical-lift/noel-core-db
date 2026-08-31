do $$
declare
  v_circle_id uuid;
  v_alice_id uuid;
  v_rundell_id uuid;
  v_randolph_id uuid;
begin
  select id into v_circle_id
  from wnph.source_circles
  where canonical_key = 'wnph:circle:mary-randall'
  order by created_at
  limit 1;

  if v_circle_id is null then
    insert into wnph.source_circles (
      canonical_key,
      canonical_label,
      circle_type,
      status,
      notes
    ) values (
      'wnph:circle:mary-randall',
      'Mary Randall Circle',
      'thematic_source',
      'research_only',
      'Research grouping for the Mary Randall functional/source-circle inquiry. Membership does not assert shared identity, pseudonymy, transmission lineage, or common authorship; each creator retains her own public attribution.'
    )
    returning id into v_circle_id;
  end if;

  select id into v_alice_id
  from wnph.creator_authorities
  where canonical_key = 'alice-ross-colver'
  limit 1;

  if v_alice_id is not null and not exists (
    select 1 from wnph.source_circle_memberships
    where source_circle_id = v_circle_id and creator_id = v_alice_id
  ) then
    insert into wnph.source_circle_memberships (
      source_circle_id,
      creator_id,
      relationship_type,
      evidence_status,
      mechanism_status,
      confidence,
      notes
    ) values (
      v_circle_id,
      v_alice_id,
      'unknown',
      'research_only',
      'unknown',
      'open',
      'Previously designated member of the Mary Randall Circle. Relationship and mechanism remain unresolved; public attribution remains Alice Ross Colver.'
    );
  end if;

  insert into wnph.creator_authorities (
    canonical_key,
    preferred_label,
    creator_type,
    status,
    identity_confidence,
    notes
  ) values (
    'maria-rundell',
    'Maria Rundell',
    'person',
    'established',
    'high',
    'Creator authority registered for WNPH cookbook acquisition and source-circle research.'
  )
  on conflict (canonical_key) do update
    set preferred_label = excluded.preferred_label
  returning id into v_rundell_id;

  insert into wnph.creator_authorities (
    canonical_key,
    preferred_label,
    creator_type,
    status,
    identity_confidence,
    notes
  ) values (
    'mary-randolph',
    'Mary Randolph',
    'person',
    'established',
    'high',
    'Creator authority registered for WNPH cookbook acquisition and source-circle research.'
  )
  on conflict (canonical_key) do update
    set preferred_label = excluded.preferred_label
  returning id into v_randolph_id;

  if not exists (
    select 1 from wnph.source_circle_memberships
    where source_circle_id = v_circle_id and creator_id = v_rundell_id
  ) then
    insert into wnph.source_circle_memberships (
      source_circle_id,
      creator_id,
      relationship_type,
      evidence_status,
      mechanism_status,
      confidence,
      notes
    ) values (
      v_circle_id,
      v_rundell_id,
      'functional_alignment',
      'research_only',
      'unknown',
      'open',
      'Included by research directive alongside the Mary Randall inquiry because the domestic-cookery corpus may preserve the same functional pattern. No identity or transmission claim is made.'
    );
  end if;

  if not exists (
    select 1 from wnph.source_circle_memberships
    where source_circle_id = v_circle_id and creator_id = v_randolph_id
  ) then
    insert into wnph.source_circle_memberships (
      source_circle_id,
      creator_id,
      relationship_type,
      evidence_status,
      mechanism_status,
      confidence,
      notes
    ) values (
      v_circle_id,
      v_randolph_id,
      'functional_alignment',
      'research_only',
      'unknown',
      'open',
      'Included by research directive alongside the Mary Randall inquiry because the domestic-cookery corpus may preserve the same functional pattern. No identity or transmission claim is made.'
    );
  end if;
end $$;