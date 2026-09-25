-- Production-synchronized hardening: person candidate source thresholds.
-- Applied to production as 20260925000644.
-- Reassert the current hardened preview contract. Government-authoritative
-- evidence requires confidence >= 0.980 for automatic promotion; official
-- first-party / owner-verified evidence requires confidence >= 0.960.

CREATE OR REPLACE FUNCTION local_intel.preview_person_discovery_candidate_promotion_v1(p_candidate_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_candidate local_intel.person_discovery_candidates%rowtype;
  v_org local_intel.entities%rowtype;
  v_source local_intel.sources%rowtype;
  v_source_strength text;
  v_full_name boolean:=false;
  v_source_strong boolean:=false;
  v_source_fresh boolean:=false;
  v_exact_match_count integer:=0;
  v_exact_person_id uuid;
  v_exact_anchor boolean:=false;
  v_action text;
  v_promotable boolean:=false;
  v_reasons text[]:='{}'::text[];
  v_relationship_kinds text[]:='{}'::text[];
  v_direct_contact_count integer:=0;
  v_fingerprint text;
begin
  select * into v_candidate
  from local_intel.person_discovery_candidates
  where id=p_candidate_id;

  if v_candidate.id is null then
    raise exception 'Person discovery candidate not found.' using errcode='P0002';
  end if;

  select * into v_org
  from local_intel.entities
  where id=v_candidate.organization_entity_id
    and status='active';

  if v_org.id is null then
    return jsonb_build_object(
      'candidateId',v_candidate.id,
      'promotable',false,
      'action','blocked',
      'reasons',jsonb_build_array('organization_missing_or_inactive')
    );
  end if;

  if v_candidate.source_id is not null then
    select * into v_source
    from local_intel.sources
    where id=v_candidate.source_id;

    select esc.default_evidence_strength
      into v_source_strength
    from local_intel.evidence_source_classes esc
    where esc.source_class_key=v_source.source_class_key;
  end if;

  v_full_name :=
    coalesce(array_length(regexp_split_to_array(btrim(v_candidate.candidate_name),E'\\s+'),1),0) >= 2;

  v_source_strong :=
    v_source.id is not null
    and (
      (v_source_strength in ('official_source','owner_verified') and v_candidate.confidence >= 0.960)
      or
      (v_source_strength='government_authoritative' and v_candidate.confidence >= 0.980)
    );

  v_source_fresh :=
    v_source.id is not null
    and coalesce(v_source.retrieved_at,now()) >= now()-interval '395 days';

  select
    count(*),
    (array_agg(pe.id order by pe.id))[1]
    into v_exact_match_count,v_exact_person_id
  from local_intel.entities pe
  where pe.entity_type='person'
    and pe.status='active'
    and local_intel.normalize_entity_name_for_resolution_v2(pe.name)
        = local_intel.normalize_entity_name_for_resolution_v2(v_candidate.candidate_name);

  if v_exact_match_count=1 then
    v_exact_anchor :=
      exists(
        select 1
        from local_intel.entity_relationships r
        where r.subject_entity_id=v_exact_person_id
          and r.object_entity_id=v_candidate.organization_entity_id
          and r.is_current
          and r.truth_state in ('observed','accepted_current')
          and r.conflict_state='none'
      )
      or exists(
        select 1
        from local_intel.contact_points cp
        where cp.entity_id=v_exact_person_id
          and (
            (
              v_candidate.candidate_email is not null
              and cp.contact_type='email'
              and cp.normalized_value=lower(btrim(v_candidate.candidate_email))
            )
            or
            (
              v_candidate.candidate_phone is not null
              and cp.contact_type='phone'
              and cp.normalized_value=regexp_replace(v_candidate.candidate_phone,'[^0-9]','','g')
            )
          )
      );
  end if;

  select count(*)
    into v_direct_contact_count
  from local_intel.contact_points cp
  where cp.entity_id=v_candidate.organization_entity_id
    and cp.contact_scope in ('direct_person','direct_role')
    and (
      (
        v_candidate.candidate_email is not null
        and cp.contact_type='email'
        and cp.normalized_value=lower(btrim(v_candidate.candidate_email))
      )
      or
      (
        v_candidate.candidate_phone is not null
        and cp.contact_type='phone'
        and cp.normalized_value=regexp_replace(v_candidate.candidate_phone,'[^0-9]','','g')
      )
    );

  if lower(coalesce(v_candidate.candidate_role,'')) like '%owner%' then
    v_relationship_kinds:=array_append(v_relationship_kinds,'owns');
  end if;
  if lower(coalesce(v_candidate.candidate_role,'')) like '%founder%' then
    v_relationship_kinds:=array_append(v_relationship_kinds,'founded');
  end if;
  if nullif(btrim(coalesce(v_candidate.candidate_role,'')),'') is not null then
    v_relationship_kinds:=array_append(v_relationship_kinds,'holds_role_at');
  end if;
  if lower(coalesce(v_candidate.candidate_role,'')) like '%primary contact%' then
    v_relationship_kinds:=array_append(v_relationship_kinds,'primary_contact_for');
  end if;

  select coalesce(array_agg(distinct x order by x),'{}'::text[])
    into v_relationship_kinds
  from unnest(v_relationship_kinds) x;

  if v_candidate.review_state='canonicalized' and v_candidate.matched_person_entity_id is not null then
    v_promotable:=true;
    v_action:='already_canonicalized';
  elsif v_candidate.review_state<>'pending' then
    v_action:='blocked';
    v_reasons:=array_append(v_reasons,'candidate_review_state_'||v_candidate.review_state);
  elsif not v_full_name then
    v_action:='blocked';
    v_reasons:=array_append(v_reasons,'full_person_name_required');
  elsif v_candidate.confidence < 0.960 then
    v_action:='blocked';
    v_reasons:=array_append(v_reasons,'candidate_confidence_below_0_960');
  elsif not v_source_strong then
    v_action:='review_required';
    v_reasons:=array_append(v_reasons,'strong_current_source_required_for_automatic_promotion');
  elsif not v_source_fresh then
    v_action:='review_required';
    v_reasons:=array_append(v_reasons,'source_refresh_required');
  elsif v_exact_match_count=0 then
    v_promotable:=true;
    v_action:='create_person';
  elsif v_exact_match_count=1 and v_exact_anchor then
    v_promotable:=true;
    v_action:='reuse_person';
  elsif v_exact_match_count=1 then
    v_action:='review_required';
    v_reasons:=array_append(v_reasons,'exact_name_person_exists_without_second_identity_anchor');
  else
    v_action:='review_required';
    v_reasons:=array_append(v_reasons,'multiple_exact_name_person_matches');
  end if;

  v_fingerprint:=md5(concat_ws('|',
    v_candidate.id::text,
    v_candidate.organization_entity_id::text,
    v_candidate.candidate_name,
    coalesce(v_candidate.candidate_role,''),
    coalesce(v_candidate.candidate_email,''),
    coalesce(v_candidate.candidate_phone,''),
    v_candidate.confidence::text,
    v_candidate.review_state,
    coalesce(v_candidate.source_id::text,''),
    coalesce(v_source.source_class_key,''),
    coalesce(v_source.retrieved_at::text,''),
    coalesce(v_source_strength,'')
  ));

  return jsonb_build_object(
    'contractVersion','person_discovery_candidate_promotion_preview_v1',
    'candidateId',v_candidate.id,
    'organizationEntityId',v_candidate.organization_entity_id,
    'organizationName',v_org.name,
    'candidateName',v_candidate.candidate_name,
    'candidateRole',v_candidate.candidate_role,
    'candidateConfidence',v_candidate.confidence,
    'reviewState',v_candidate.review_state,
    'source',jsonb_strip_nulls(jsonb_build_object(
      'sourceId',v_candidate.source_id,
      'sourceUrl',v_source.source_url,
      'sourceClassKey',v_source.source_class_key,
      'evidenceStrength',v_source_strength,
      'retrievedAt',v_source.retrieved_at
    )),
    'warrant',jsonb_build_object(
      'fullName',v_full_name,
      'strongSource',v_source_strong,
      'freshSource',v_source_fresh,
      'exactPersonMatchCount',v_exact_match_count,
      'exactPersonId',v_exact_person_id,
      'exactMatchHasSecondAnchor',v_exact_anchor,
      'directContactRoutesEligibleForPerson',v_direct_contact_count
    ),
    'proposedRelationshipKinds',to_jsonb(v_relationship_kinds),
    'promotable',v_promotable,
    'action',v_action,
    'reasons',to_jsonb(v_reasons),
    'previewFingerprint',v_fingerprint,
    'truthBoundary',jsonb_build_object(
      'candidateIsCanonicalPerson',false,
      'organizationGenericContactBecomesPersonContact',false,
      'localContextIsIdentityAuthority',false
    )
  );
end
$function$
;

comment on function local_intel.preview_person_discovery_candidate_promotion_v1(uuid) is
  'Read-only warrant preview for promoting a person discovery candidate into canonical Shared Intelligence person identity. Requires full name, high confidence, strong fresh evidence, and collision-safe identity resolution.';
