-- Repair claimant-safe projection column qualification.

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
    count(*) filter (where w.object_public_name is not null)::integer,
    coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'relationshipKind',w.relationship_kind,
        'roleTitle',w.role_title,
        'relatedEntity',jsonb_build_object(
          'name',w.object_public_name,
          'entityType',oe.entity_type
        ),
        'verificationState',w.verification_state,
        'lastVerifiedAt',w.last_verified_at
      ))
      order by w.relationship_kind,w.object_public_name,w.relationship_id
    ) filter (where w.object_public_name is not null),'[]'::jsonb)
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
