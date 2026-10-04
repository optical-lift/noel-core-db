-- Atlas claimant-safe identity disclosure membrane v1.
-- Resolution authority and claimant disclosure authority are separate.

create table if not exists local_intel.entity_relationship_claimant_disclosures (
  relationship_id uuid primary key
    references local_intel.entity_relationships(id) on delete cascade,
  claimant_visibility text not null default 'hidden',
  disclosure_basis_kind text not null,
  disclosure_source_id uuid references local_intel.sources(id) on delete set null,
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entity_relationship_claimant_disclosures_visibility_v1
    check (claimant_visibility in ('hidden','public_claimant_visible')),
  constraint entity_relationship_claimant_disclosures_basis_v1
    check (disclosure_basis_kind in ('public_source','operator_hidden')),
  constraint entity_relationship_claimant_disclosures_effective_v1
    check (effective_until is null or effective_until >= effective_from),
  constraint entity_relationship_claimant_disclosures_metadata_v1
    check (jsonb_typeof(metadata)='object')
);

comment on table local_intel.entity_relationship_claimant_disclosures is
  'Explicit disclosure membrane for canonical relationships shown to a person claiming the subject identity. Absence of a row means hidden. Resolution or relationship truth alone is not disclosure authority.';

alter table local_intel.entity_relationship_claimant_disclosures
  enable row level security;

revoke all on table local_intel.entity_relationship_claimant_disclosures
  from public,anon,authenticated;
grant select,insert,update,delete
  on table local_intel.entity_relationship_claimant_disclosures
  to service_role;

create or replace function local_intel.set_entity_relationship_claimant_disclosure_updated_at_v1()
returns trigger
language plpgsql
set search_path to 'pg_catalog','local_intel'
as $function$
begin
  new.updated_at=now();
  return new;
end
$function$;

drop trigger if exists entity_relationship_claimant_disclosures_updated_at_v1
  on local_intel.entity_relationship_claimant_disclosures;
create trigger entity_relationship_claimant_disclosures_updated_at_v1
before update on local_intel.entity_relationship_claimant_disclosures
for each row execute function local_intel.set_entity_relationship_claimant_disclosure_updated_at_v1();

create or replace function local_intel.set_entity_relationship_claimant_disclosure_service_v1(
  p_relationship_id uuid,
  p_claimant_visibility text,
  p_disclosure_basis_kind text,
  p_effective_until timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','local_intel'
as $function$
declare
  v_visibility text:=lower(btrim(coalesce(p_claimant_visibility,'')));
  v_basis text:=lower(btrim(coalesce(p_disclosure_basis_kind,'')));
  v_relationship local_intel.entity_relationships%rowtype;
  v_source local_intel.sources%rowtype;
  v_source_class local_intel.evidence_source_classes%rowtype;
  v_row local_intel.entity_relationship_claimant_disclosures%rowtype;
begin
  if v_visibility not in ('hidden','public_claimant_visible') then
    raise exception 'Invalid claimant visibility.' using errcode='22023';
  end if;

  if v_basis not in ('public_source','operator_hidden') then
    raise exception 'Invalid claimant disclosure basis.' using errcode='22023';
  end if;

  if p_effective_until is not null and p_effective_until < now() then
    raise exception 'Claimant disclosure effective-until cannot already be past.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Claimant disclosure metadata must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_relationship
  from local_intel.entity_relationships r
  where r.id=p_relationship_id;

  if v_relationship.id is null then
    raise exception 'Canonical entity relationship not found.' using errcode='P0002';
  end if;

  if v_visibility='public_claimant_visible' then
    if v_basis<>'public_source' then
      raise exception 'Public claimant visibility v1 requires public-source basis.'
        using errcode='22023';
    end if;

    if not v_relationship.is_current
       or v_relationship.conflict_state<>'none'
       or v_relationship.truth_state<>'accepted_current' then
      raise exception 'Only current, accepted, non-conflicted relationships may be claimant-visible.'
        using errcode='22023';
    end if;

    if v_relationship.source_id is null then
      raise exception 'Public claimant visibility requires a source-backed relationship.'
        using errcode='22023';
    end if;

    select * into v_source
    from local_intel.sources s
    where s.id=v_relationship.source_id;

    if v_source.id is null or v_source.source_class_key is null then
      raise exception 'Relationship source lacks Evidence + Disclosure classification.'
        using errcode='22023';
    end if;

    select * into v_source_class
    from local_intel.evidence_source_classes c
    where c.source_class_key=v_source.source_class_key
      and c.class_state='active';

    if v_source_class.source_class_key is null
       or not ('directory_display'=any(v_source_class.allowed_uses))
       or local_intel.disclosure_posture_rank_v1(
            v_source_class.maximum_disclosure_posture
          ) < local_intel.disclosure_posture_rank_v1('public_directory') then
      raise exception 'Relationship source class does not authorize claimant-visible public disclosure.'
        using errcode='22023';
    end if;
  else
    if v_basis<>'operator_hidden' then
      raise exception 'Hidden claimant disclosure v1 requires operator_hidden basis.'
        using errcode='22023';
    end if;
  end if;

  insert into local_intel.entity_relationship_claimant_disclosures(
    relationship_id,claimant_visibility,disclosure_basis_kind,
    disclosure_source_id,effective_from,effective_until,metadata
  )
  values(
    v_relationship.id,v_visibility,v_basis,
    case when v_visibility='public_claimant_visible'
      then v_relationship.source_id else null end,
    now(),p_effective_until,coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (relationship_id)
  do update set
    claimant_visibility=excluded.claimant_visibility,
    disclosure_basis_kind=excluded.disclosure_basis_kind,
    disclosure_source_id=excluded.disclosure_source_id,
    effective_from=excluded.effective_from,
    effective_until=excluded.effective_until,
    metadata=local_intel.entity_relationship_claimant_disclosures.metadata
      || excluded.metadata,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','entity_relationship_claimant_disclosure_v1',
    'relationshipId',v_row.relationship_id,
    'claimantVisibility',v_row.claimant_visibility,
    'disclosureBasisKind',v_row.disclosure_basis_kind,
    'effectiveFrom',v_row.effective_from,
    'effectiveUntil',v_row.effective_until
  );
end
$function$;

create or replace function atlas.claimant_safe_identity_projection_service_v1(
  p_canonical_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_entity local_intel.entities%rowtype;
  v_facts jsonb;
  v_affiliations jsonb;
  v_display_name text;
  v_public_fact_count integer;
  v_affiliation_count integer;
  v_reveal_level text;
begin
  select * into v_entity
  from local_intel.entities e
  where e.id=p_canonical_entity_id;

  if v_entity.id is null then
    raise exception 'Canonical entity not found.' using errcode='P0002';
  end if;

  with safe_claims as (
    select c.*
    from local_intel.entity_evidence_claims c
    where c.entity_id=p_canonical_entity_id
      and c.lifecycle_state='current'
      and c.disclosure_posture in ('public_directory','public_contactable')
      and 'directory_display'=any(c.permitted_uses)
      and (c.valid_from is null or c.valid_from<=current_date)
      and (c.valid_until is null or c.valid_until>=current_date)
      and not exists(
        select 1
        from local_intel.entity_contact_suppressions s
        where s.entity_id=c.entity_id
          and s.suppression_state='active'
          and (s.effective_until is null or s.effective_until>now())
          and s.suppression_scope in ('directory_display','all_use')
          and (s.evidence_claim_id is null or s.evidence_claim_id=c.id)
      )
  )
  select
    count(*)::integer,
    (
      select sc.value_text
      from safe_claims sc
      where sc.claim_kind in ('display_name','name','legal_name','business_name')
      order by
        case sc.evidence_strength
          when 'owner_verified' then 1
          when 'government_authoritative' then 2
          when 'official_source' then 3
          when 'third_party_observed' then 4
          else 5
        end,
        sc.last_verified_at desc nulls last,
        sc.created_at desc,
        sc.id
      limit 1
    ),
    coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'claimKind',sc.claim_kind,
        'value',sc.value_text,
        'evidenceStrength',sc.evidence_strength,
        'sourceClassKey',sc.source_class_key,
        'lastVerifiedAt',sc.last_verified_at
      ))
      order by sc.claim_kind,sc.value_text,sc.id
    ) filter (where sc.id is not null),'[]'::jsonb)
  into v_public_fact_count,v_display_name,v_facts
  from safe_claims sc;

  with visible_relationships as (
    select
      r.id as relationship_id,
      r.relationship_kind,
      r.role_title,
      r.object_entity_id,
      r.verification_state,
      r.last_verified_at
    from local_intel.entity_relationships r
    join local_intel.entity_relationship_claimant_disclosures d
      on d.relationship_id=r.id
     and d.claimant_visibility='public_claimant_visible'
     and d.effective_from<=now()
     and (d.effective_until is null or d.effective_until>now())
    where r.subject_entity_id=p_canonical_entity_id
      and r.is_current
      and r.truth_state='accepted_current'
      and r.conflict_state='none'
  ),
  with_public_object_name as (
    select
      vr.*,
      (
        select c.value_text
        from local_intel.entity_evidence_claims c
        where c.entity_id=vr.object_entity_id
          and c.lifecycle_state='current'
          and c.disclosure_posture in ('public_directory','public_contactable')
          and 'directory_display'=any(c.permitted_uses)
          and c.claim_kind in ('display_name','name','legal_name','business_name')
          and (c.valid_from is null or c.valid_from<=current_date)
          and (c.valid_until is null or c.valid_until>=current_date)
          and not exists(
            select 1
            from local_intel.entity_contact_suppressions s
            where s.entity_id=c.entity_id
              and s.suppression_state='active'
              and (s.effective_until is null or s.effective_until>now())
              and s.suppression_scope in ('directory_display','all_use')
              and (s.evidence_claim_id is null or s.evidence_claim_id=c.id)
          )
        order by
          case c.evidence_strength
            when 'owner_verified' then 1
            when 'government_authoritative' then 2
            when 'official_source' then 3
            when 'third_party_observed' then 4
            else 5
          end,
          c.last_verified_at desc nulls last,
          c.created_at desc,
          c.id
        limit 1
      ) as object_public_name
    from visible_relationships vr
  )
  select
    count(*) filter (where object_public_name is not null)::integer,
    coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'relationshipKind',relationship_kind,
        'roleTitle',role_title,
        'relatedEntity',jsonb_build_object(
          'name',object_public_name,
          'entityType',oe.entity_type
        ),
        'verificationState',verification_state,
        'lastVerifiedAt',last_verified_at
      ))
      order by relationship_kind,object_public_name,relationship_id
    ) filter (where object_public_name is not null),'[]'::jsonb)
  into v_affiliation_count,v_affiliations
  from with_public_object_name w
  join local_intel.entities oe on oe.id=w.object_entity_id;

  if coalesce(v_public_fact_count,0)=0 then
    v_reveal_level:='anonymous_match';
    v_display_name:=null;
    v_facts:='[]'::jsonb;
    v_affiliations:='[]'::jsonb;
    v_affiliation_count:=0;
  elsif coalesce(v_affiliation_count,0)>0 then
    v_reveal_level:='public_identity_with_affiliations';
  else
    v_reveal_level:='public_identity';
  end if;

  return jsonb_build_object(
    'contractVersion','claimant_safe_identity_projection_v1',
    'canonicalEntityId',p_canonical_entity_id,
    'revealLevel',v_reveal_level,
    'entityType',case when v_reveal_level='anonymous_match'
      then null else v_entity.entity_type end,
    'displayName',v_display_name,
    'publicFacts',coalesce(v_facts,'[]'::jsonb),
    'publicAffiliations',coalesce(v_affiliations,'[]'::jsonb),
    'claimantMessage',case
      when v_reveal_level='anonymous_match'
        then 'We found an existing identity that may be yours.'
      when v_reveal_level='public_identity'
        then 'We found an existing public identity that may be yours.'
      else 'We found an existing public identity and public affiliation that may be yours.'
    end
  );
end
$function$;

comment on function atlas.claimant_safe_identity_projection_service_v1(uuid) is
  'Claimant-safe identity membrane. Returns only public/shared facts with explicit directory-display authority and explicitly claimant-visible public relationships. It never reads Ledger source payloads, blind identifiers, resolver match evidence, or another Ledger private overlay.';

revoke all on function local_intel.set_entity_relationship_claimant_disclosure_service_v1(
  uuid,text,text,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function local_intel.set_entity_relationship_claimant_disclosure_service_v1(
  uuid,text,text,timestamptz,jsonb
) to service_role;

revoke all on function atlas.claimant_safe_identity_projection_service_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.claimant_safe_identity_projection_service_v1(uuid)
  to service_role;
