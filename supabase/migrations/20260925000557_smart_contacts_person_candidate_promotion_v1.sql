-- Production-synchronized migration: Smart Contacts person candidate promotion v1
-- Applied to production as 20260925000557.

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

CREATE OR REPLACE FUNCTION local_intel.promote_person_discovery_candidate_service_v1(p_candidate_id uuid, p_expected_preview_fingerprint text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_candidate local_intel.person_discovery_candidates%rowtype;
  v_org local_intel.entities%rowtype;
  v_source local_intel.sources%rowtype;
  v_source_strength text;
  v_preview jsonb;
  v_action text;
  v_person_id uuid;
  v_person_stable_key text;
  v_slug text;
  v_verification_state text;
  v_relationship_kind text;
  v_relationship_kinds text[]:='{}'::text[];
  v_relationship_ids uuid[]:='{}'::uuid[];
  v_relationship_id uuid;
  v_contact_count integer:=0;
begin
  select * into v_candidate
  from local_intel.person_discovery_candidates
  where id=p_candidate_id
  for update;

  if v_candidate.id is null then
    raise exception 'Person discovery candidate not found.' using errcode='P0002';
  end if;

  if v_candidate.review_state='canonicalized'
     and v_candidate.matched_person_entity_id is not null then
    return jsonb_build_object(
      'ok',true,
      'changed',false,
      'contractVersion','person_discovery_candidate_promotion_v1',
      'candidateId',v_candidate.id,
      'personEntityId',v_candidate.matched_person_entity_id,
      'action','already_canonicalized'
    );
  end if;

  v_preview:=local_intel.preview_person_discovery_candidate_promotion_v1(p_candidate_id);

  if p_expected_preview_fingerprint is not null
     and p_expected_preview_fingerprint is distinct from v_preview->>'previewFingerprint' then
    raise exception 'Person candidate promotion preview changed; refresh preview before promotion.'
      using errcode='40001';
  end if;

  if not coalesce((v_preview->>'promotable')::boolean,false) then
    raise exception 'Person candidate is not automatically promotable: %',
      coalesce(v_preview->'reasons','[]'::jsonb)::text
      using errcode='23514';
  end if;

  v_action:=v_preview->>'action';

  select * into v_org
  from local_intel.entities
  where id=v_candidate.organization_entity_id
    and status='active';

  select * into v_source
  from local_intel.sources
  where id=v_candidate.source_id;

  select esc.default_evidence_strength
    into v_source_strength
  from local_intel.evidence_source_classes esc
  where esc.source_class_key=v_source.source_class_key;

  v_verification_state:=case
    when v_source_strength in ('official_source','owner_verified','government_authoritative')
      then 'official_source_current'
    else 'public_source_current'
  end;

  if v_action='reuse_person' then
    v_person_id:=(v_preview#>>'{warrant,exactPersonId}')::uuid;
  elsif v_action='create_person' then
    v_slug:=trim(both '-' from regexp_replace(
      lower(btrim(v_candidate.candidate_name)),
      '[^a-z0-9]+','-','g'
    ));
    if v_slug='' then
      v_slug:='person-'||substr(replace(v_candidate.id::text,'-',''),1,8);
    end if;
    v_person_stable_key:='person:'||v_slug;

    if exists(
      select 1
      from local_intel.entities e
      where e.local_context_id=v_org.local_context_id
        and e.stable_key=v_person_stable_key
    ) then
      v_person_stable_key:=v_person_stable_key||'-'||substr(replace(v_candidate.id::text,'-',''),1,8);
    end if;

    insert into local_intel.entities(
      id,stable_key,entity_type,name,status,verification_state,last_verified_at,
      metadata,local_context_id
    )
    values(
      gen_random_uuid(),
      v_person_stable_key,
      'person',
      v_candidate.candidate_name,
      'active',
      v_verification_state,
      now(),
      jsonb_build_object(
        'canonicalized_from','person_discovery_candidates',
        'candidate_id',v_candidate.id,
        'source_id',v_candidate.source_id,
        'source_class_key',v_source.source_class_key,
        'organization_entity_id',v_candidate.organization_entity_id,
        'local_context_compatibility_inherited',true,
        'identity_authority','shared_intelligence'
      ),
      v_org.local_context_id
    )
    returning id into v_person_id;
  else
    raise exception 'Unexpected promotion action %',v_action using errcode='23514';
  end if;

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

  foreach v_relationship_kind in array v_relationship_kinds
  loop
    insert into local_intel.entity_relationships(
      subject_entity_id,relationship_kind,object_entity_id,role_title,is_current,
      verification_state,last_verified_at,source_id,metadata,truth_state,
      current_confidence,last_seen_current_at,conflict_state,resolution_basis
    )
    values(
      v_person_id,
      v_relationship_kind,
      v_candidate.organization_entity_id,
      v_candidate.candidate_role,
      true,
      v_verification_state,
      now(),
      v_candidate.source_id,
      jsonb_build_object(
        'promoted_from_candidate_id',v_candidate.id,
        'promotion_contract','person_discovery_candidate_promotion_v1'
      ),
      'accepted_current',
      v_candidate.confidence,
      now(),
      'none',
      'person_discovery_candidate_promotion_v1'
    )
    on conflict (
      subject_entity_id,relationship_kind,object_entity_id,
      (coalesce(role_title,''))
    ) where is_current
    do update set
      verification_state=excluded.verification_state,
      last_verified_at=excluded.last_verified_at,
      source_id=coalesce(excluded.source_id,local_intel.entity_relationships.source_id),
      metadata=coalesce(local_intel.entity_relationships.metadata,'{}'::jsonb)||excluded.metadata,
      truth_state='accepted_current',
      current_confidence=greatest(
        coalesce(local_intel.entity_relationships.current_confidence,0),
        excluded.current_confidence
      ),
      last_seen_current_at=excluded.last_seen_current_at,
      conflict_state='none',
      conflict_reason=null,
      resolution_basis=excluded.resolution_basis,
      updated_at=now()
    returning id into v_relationship_id;

    v_relationship_ids:=array_append(v_relationship_ids,v_relationship_id);
  end loop;

  insert into local_intel.contact_points(
    id,entity_id,contact_type,contact_value,normalized_value,context,contact_scope,
    is_primary,visibility,verification_state,deliverability_state,marketing_status,
    verified_at,last_checked_at,source_id,metadata
  )
  select
    gen_random_uuid(),
    v_person_id,
    cp.contact_type,
    cp.contact_value,
    cp.normalized_value,
    cp.context,
    'direct',
    cp.is_primary,
    cp.visibility,
    cp.verification_state,
    cp.deliverability_state,
    cp.marketing_status,
    cp.verified_at,
    cp.last_checked_at,
    cp.source_id,
    coalesce(cp.metadata,'{}'::jsonb)||jsonb_build_object(
      'promoted_from_organization_contact_point_id',cp.id,
      'promoted_from_candidate_id',v_candidate.id,
      'promotion_contract','person_discovery_candidate_promotion_v1'
    )
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
    )
  on conflict (entity_id,contact_type,normalized_value) do update
  set
    contact_value=excluded.contact_value,
    contact_scope='direct',
    visibility=excluded.visibility,
    verification_state=excluded.verification_state,
    deliverability_state=excluded.deliverability_state,
    marketing_status=excluded.marketing_status,
    verified_at=greatest(local_intel.contact_points.verified_at,excluded.verified_at),
    last_checked_at=greatest(local_intel.contact_points.last_checked_at,excluded.last_checked_at),
    source_id=coalesce(excluded.source_id,local_intel.contact_points.source_id),
    metadata=coalesce(local_intel.contact_points.metadata,'{}'::jsonb)||excluded.metadata,
    updated_at=now();

  get diagnostics v_contact_count=row_count;

  update local_intel.person_discovery_candidates
  set
    review_state='canonicalized',
    matched_person_entity_id=v_person_id,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'canonicalized_at',now(),
      'canonicalization_contract','person_discovery_candidate_promotion_v1',
      'canonicalization_action',v_action
    ),
    updated_at=now()
  where id=v_candidate.id;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','person_discovery_candidate_promotion_v1',
    'candidateId',v_candidate.id,
    'personEntityId',v_person_id,
    'organizationEntityId',v_candidate.organization_entity_id,
    'action',v_action,
    'relationshipKinds',to_jsonb(v_relationship_kinds),
    'relationshipIds',to_jsonb(v_relationship_ids),
    'directContactRoutesPromoted',v_contact_count,
    'truthBoundary',jsonb_build_object(
      'canonicalPersonEstablished',true,
      'organizationRelationshipCreated',false,
      'genericOrganizationContactsCopiedToPerson',false,
      'localContextUsedAsIdentityAuthority',false
    )
  );
end
$function$
;

revoke all on function local_intel.preview_person_discovery_candidate_promotion_v1(uuid)
  from public,anon,authenticated;
grant execute on function local_intel.preview_person_discovery_candidate_promotion_v1(uuid)
  to service_role;

revoke all on function local_intel.promote_person_discovery_candidate_service_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function local_intel.promote_person_discovery_candidate_service_v1(uuid,text)
  to service_role;

comment on function local_intel.preview_person_discovery_candidate_promotion_v1(uuid) is
  'Read-only warrant preview for promoting a person discovery candidate into canonical Shared Intelligence person identity. Requires full name, high confidence, strong fresh evidence, and collision-safe identity resolution.';

comment on function local_intel.promote_person_discovery_candidate_service_v1(uuid,text) is
  'Service-only promotion membrane from person discovery candidate to canonical Shared Intelligence Person + source-backed current organization relationships. Generic organization contact routes are never copied to the person.';
