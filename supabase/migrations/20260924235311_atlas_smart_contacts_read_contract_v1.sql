-- Production-synchronized migration: Atlas Smart Contacts read contract v1
-- Applied to Supabase as migration 20260924235311.

create or replace view local_intel.v_smart_contact_signals_v1 as
 WITH mapped AS (
         SELECT ec.id AS evidence_claim_id,
            ec.entity_id,
            ec.claim_kind,
            ec.value_text,
            ec.normalized_value,
            ec.source_id,
            ec.source_class_key,
            ec.evidence_strength,
            ec.disclosure_posture,
            ec.lifecycle_state,
            ec.observed_at,
            ec.last_verified_at,
            ec.metadata,
            x.signal_key
           FROM local_intel.entity_evidence_claims ec
             CROSS JOIN LATERAL unnest(
                CASE ec.claim_kind
                    WHEN 'wholesale_purchase_behavior'::text THEN ARRAY['commercial_buyer'::text, 'wholesale_buyer'::text, 'cut_flower_buyer'::text]
                    WHEN 'local_flower_sourcing_preference'::text THEN ARRAY['commercial_buyer'::text, 'local_sourcing'::text, 'cut_flower_buyer'::text]
                    WHEN 'local_exchange_sourcing'::text THEN ARRAY['commercial_buyer'::text, 'local_sourcing'::text, 'cut_flower_buyer'::text]
                    WHEN 'flower_supply_cadence'::text THEN ARRAY['commercial_buyer'::text, 'cut_flower_buyer'::text, 'recurring_flower_demand'::text]
                    WHEN 'local_flower_use'::text THEN ARRAY['commercial_buyer'::text, 'local_sourcing'::text, 'cut_flower_buyer'::text]
                    WHEN 'fresh_flower_demand_context'::text THEN ARRAY['commercial_buyer'::text, 'cut_flower_buyer'::text, 'fresh_flower_demand'::text]
                    WHEN 'documented_exchange_buyer_history'::text THEN ARRAY['commercial_buyer'::text, 'wholesale_buyer'::text, 'cut_flower_buyer'::text, 'historical_buyer'::text]
                    WHEN 'supplier_capability'::text THEN ARRAY['commercial_supplier'::text, 'cut_flower_supplier'::text]
                    WHEN 'distribution_capability'::text THEN ARRAY['commercial_supplier'::text, 'distribution_capable'::text]
                    WHEN 'ordering_logistics'::text THEN ARRAY['commercial_supplier'::text, 'ordering_process_known'::text]
                    WHEN 'market_membership'::text THEN ARRAY['commercial_supplier'::text, 'market_member'::text]
                    WHEN 'event_flower_service'::text THEN ARRAY['commercial_supplier'::text, 'cut_flower_supplier'::text, 'fresh_flower_service'::text]
                    WHEN 'commercial_role'::text THEN ARRAY['commercially_relevant'::text]
                    WHEN 'decision_contact'::text THEN ARRAY['decision_contact_known'::text]
                    WHEN 'flower_contact_route'::text THEN ARRAY['public_contact_route'::text]
                    WHEN 'public_contact_route'::text THEN ARRAY['public_contact_route'::text]
                    ELSE ARRAY[]::text[]
                END) x(signal_key)
          WHERE (ec.disclosure_posture = ANY (ARRAY['public_directory'::text, 'public_contactable'::text])) AND ('directory_display'::text = ANY (ec.permitted_uses))
        )
 SELECT mapped.evidence_claim_id,
    mapped.entity_id,
    mapped.claim_kind,
    mapped.value_text,
    mapped.normalized_value,
    mapped.source_id,
    mapped.source_class_key,
    mapped.evidence_strength,
    mapped.disclosure_posture,
    mapped.lifecycle_state,
    mapped.observed_at,
    mapped.last_verified_at,
    mapped.metadata,
    mapped.signal_key
   FROM mapped
UNION ALL
 SELECT ec.id AS evidence_claim_id,
    ec.entity_id,
    ec.claim_kind,
    ec.value_text,
    ec.normalized_value,
    ec.source_id,
    ec.source_class_key,
    ec.evidence_strength,
    ec.disclosure_posture,
    ec.lifecycle_state,
    ec.observed_at,
    ec.last_verified_at,
    ec.metadata,
    'wholesale_supplier'::text AS signal_key
   FROM local_intel.entity_evidence_claims ec
  WHERE ec.claim_kind = 'supplier_capability'::text AND (lower(COALESCE(ec.value_text, ''::text)) ~~ '%wholesale%'::text OR lower(COALESCE(ec.normalized_value, ''::text)) ~~ '%wholesale%'::text OR lower(COALESCE(ec.metadata::text, ''::text)) ~~ '%wholesale%'::text) AND (ec.disclosure_posture = ANY (ARRAY['public_directory'::text, 'public_contactable'::text])) AND ('directory_display'::text = ANY (ec.permitted_uses));;

comment on view local_intel.v_smart_contact_signals_v1 is
  'Internal Shared Intelligence semantic signal projection consumed by Atlas Smart Contacts. It translates source-backed public evidence claims into stable search signals without writing Organization intent into canonical truth.';

CREATE OR REPLACE FUNCTION atlas.smart_contacts_search_service_v1(p_organization_id uuid, p_query jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_text text;
  v_entity_types text[]:='{}'::text[];
  v_org_kinds text[]:='{}'::text[];
  v_places text[]:='{}'::text[];
  v_signal_keys text[]:='{}'::text[];
  v_claim_kinds text[]:='{}'::text[];
  v_person_terms text[]:='{}'::text[];
  v_required_contact_types text[]:='{}'::text[];
  v_signal_mode text:='all';
  v_relationship_filter text:='any';
  v_include_historical boolean:=false;
  v_require_named_person boolean:=false;
  v_require_contactable boolean:=false;
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
  v_items jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if not exists(
    select 1
    from atlas.organizations o
    where o.id=p_organization_id and o.status='active'
  ) then
    raise exception 'Organization not found or inactive.' using errcode='P0002';
  end if;

  if p_query is null or jsonb_typeof(p_query)<>'object' then
    raise exception 'Smart Contacts query must be a JSON object.' using errcode='22023';
  end if;

  v_text:=nullif(lower(btrim(p_query->>'text')),'');
  v_signal_mode:=coalesce(nullif(lower(btrim(p_query->>'signalMode')),''),'all');
  v_relationship_filter:=coalesce(nullif(lower(btrim(p_query->>'relationship')),''),'any');
  v_include_historical:=coalesce((p_query->>'includeHistoricalSignals')::boolean,false);
  v_require_named_person:=coalesce((p_query->>'requireNamedPerson')::boolean,false);
  v_require_contactable:=coalesce((p_query->>'requireContactable')::boolean,false);

  if v_signal_mode not in ('all','any') then
    raise exception 'signalMode must be all or any.' using errcode='22023';
  end if;
  if v_relationship_filter not in ('any','related','unrelated') then
    raise exception 'relationship must be any, related, or unrelated.' using errcode='22023';
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_entity_types
  from jsonb_array_elements_text(coalesce(p_query->'entityTypes','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_org_kinds
  from jsonb_array_elements_text(coalesce(p_query->'organizationKinds','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_places
  from jsonb_array_elements_text(coalesce(p_query->'placeLabels','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_signal_keys
  from jsonb_array_elements_text(coalesce(p_query->'signalKeys','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_claim_kinds
  from jsonb_array_elements_text(coalesce(p_query->'claimKinds','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_person_terms
  from jsonb_array_elements_text(coalesce(p_query->'personTerms','[]'::jsonb)) x;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[])
  into v_required_contact_types
  from jsonb_array_elements_text(coalesce(p_query->'requiredContactTypes','[]'::jsonb)) x;

  with candidate_base as (
    select
      e.id,
      e.name,
      e.entity_type,
      e.description,
      e.website_url,
      e.address_line1,
      e.city,
      e.state,
      e.postal_code,
      e.verification_state,
      e.last_verified_at,
      e.metadata,
      exists(
        select 1
        from atlas.identity_subject_external_identifiers i
        join atlas.external_relationships er
          on er.organization_id=i.organization_id
         and er.subject_id=i.subject_id
        where i.organization_id=p_organization_id
          and i.provider_key='local_intel'
          and i.identifier_type='entity_id'
          and i.identifier_normalized=e.id::text
          and i.is_current
      ) as is_related
    from local_intel.entities e
    where e.status='active'
      and (cardinality(v_entity_types)=0 or lower(e.entity_type)=any(v_entity_types))
      and (
        cardinality(v_org_kinds)=0
        or exists(
          select 1 from unnest(v_org_kinds) q
          where lower(concat_ws(' ',e.name,coalesce(e.description,''),coalesce(e.metadata::text,'')))
              like '%'||replace(q,'_',' ')||'%'
             or lower(concat_ws(' ',e.name,coalesce(e.description,''),coalesce(e.metadata::text,'')))
              like '%'||q||'%'
        )
      )
      and (
        cardinality(v_places)=0
        or exists(
          select 1 from unnest(v_places) q
          where lower(coalesce(e.city,'')) like '%'||q||'%'
             or lower(coalesce(e.state,'')) like '%'||q||'%'
             or lower(coalesce(e.address_line1,'')) like '%'||q||'%'
             or lower(coalesce(e.postal_code,''))=q
        )
      )
      and (
        v_text is null
        or lower(concat_ws(' ',e.name,coalesce(e.description,''),coalesce(e.metadata::text,''),coalesce(e.city,''),coalesce(e.state,''))) like '%'||v_text||'%'
        or exists(
          select 1
          from local_intel.entity_evidence_claims ec
          where ec.entity_id=e.id
            and ec.disclosure_posture in ('public_directory','public_contactable')
            and 'directory_display'=any(ec.permitted_uses)
            and lower(concat_ws(' ',ec.claim_kind,ec.value_text,ec.normalized_value)) like '%'||v_text||'%'
        )
      )
      and (
        cardinality(v_signal_keys)=0
        or (
          v_signal_mode='any'
          and exists(
            select 1
            from local_intel.v_smart_contact_signals_v1 sf
            where sf.entity_id=e.id
              and sf.signal_key=any(v_signal_keys)
              and (sf.lifecycle_state='current' or v_include_historical)
          )
        )
        or (
          v_signal_mode='all'
          and not exists(
            select 1
            from unnest(v_signal_keys) q
            where not exists(
              select 1
              from local_intel.v_smart_contact_signals_v1 sf
              where sf.entity_id=e.id
                and sf.signal_key=q
                and (sf.lifecycle_state='current' or v_include_historical)
            )
          )
        )
      )
      and (
        cardinality(v_claim_kinds)=0
        or not exists(
          select 1
          from unnest(v_claim_kinds) q
          where not exists(
            select 1
            from local_intel.entity_evidence_claims ec
            where ec.entity_id=e.id
              and lower(ec.claim_kind)=q
              and (ec.lifecycle_state='current' or v_include_historical)
              and ec.disclosure_posture in ('public_directory','public_contactable')
              and 'directory_display'=any(ec.permitted_uses)
          )
        )
      )
      and (
        cardinality(v_person_terms)=0
        or exists(
          select 1
          from local_intel.entity_relationships r
          join local_intel.entities pe
            on pe.id=r.subject_entity_id
           and pe.entity_type='person'
           and pe.status='active'
          where r.object_entity_id=e.id
            and r.is_current
            and r.truth_state in ('observed','accepted_current')
            and r.conflict_state='none'
            and exists(
              select 1 from unnest(v_person_terms) q
              where lower(concat_ws(' ',pe.name,coalesce(r.role_title,''),coalesce(r.role_function,''))) like '%'||q||'%'
            )
        )
        or exists(
          select 1
          from local_intel.person_discovery_candidates pdc
          where pdc.organization_entity_id=e.id
            and pdc.review_state not in ('duplicate','canonicalized')
            and exists(
              select 1 from unnest(v_person_terms) q
              where lower(concat_ws(' ',pdc.candidate_name,coalesce(pdc.candidate_role,''))) like '%'||q||'%'
            )
        )
      )
  ),
  candidate_enriched as (
    select
      b.*,
      coalesce(sig.signal_keys,'{}'::text[]) as signal_keys,
      coalesce(sig.signal_payload,'[]'::jsonb) as signal_payload,
      coalesce(sig.signal_count,0) as signal_count,
      coalesce(sig.matching_signal_count,0) as matching_signal_count,
      coalesce(claims.claim_payload,'[]'::jsonb) as evidence_payload,
      coalesce(people.canonical_people,'[]'::jsonb) as canonical_people,
      coalesce(people.canonical_count,0) as canonical_people_count,
      coalesce(candidates.candidate_people,'[]'::jsonb) as candidate_people,
      coalesce(candidates.candidate_count,0) as candidate_people_count,
      coalesce(routes.route_payload,'[]'::jsonb) as contact_routes,
      coalesce(routes.available_types,'{}'::text[]) as available_contact_types,
      coalesce(routes.route_count,0) as route_count,
      coalesce(routes.has_official_current,false) as has_official_current_route,
      greatest(
        coalesce(b.last_verified_at,'epoch'::timestamptz),
        coalesce(sig.latest_signal_verified_at,'epoch'::timestamptz),
        coalesce(routes.latest_contact_checked_at,'epoch'::timestamptz)
      ) as latest_verified_at
    from candidate_base b
    left join lateral (
      select
        array_agg(distinct sf.signal_key order by sf.signal_key) as signal_keys,
        jsonb_agg(
          jsonb_build_object(
            'signalKey',sf.signal_key,
            'claimKind',sf.claim_kind,
            'value',sf.value_text,
            'lifecycleState',sf.lifecycle_state,
            'evidenceStrength',sf.evidence_strength,
            'sourceClassKey',sf.source_class_key,
            'sourceId',sf.source_id,
            'lastVerifiedAt',sf.last_verified_at
          )
          order by sf.signal_key,sf.last_verified_at desc nulls last,sf.evidence_claim_id
        ) as signal_payload,
        count(distinct sf.signal_key)::integer as signal_count,
        count(distinct sf.signal_key) filter (where sf.signal_key=any(v_signal_keys))::integer as matching_signal_count,
        max(sf.last_verified_at) as latest_signal_verified_at
      from local_intel.v_smart_contact_signals_v1 sf
      where sf.entity_id=b.id
        and (sf.lifecycle_state='current' or v_include_historical)
    ) sig on true
    left join lateral (
      select jsonb_agg(
        jsonb_build_object(
          'claimId',ec.id,
          'claimKind',ec.claim_kind,
          'value',ec.value_text,
          'lifecycleState',ec.lifecycle_state,
          'evidenceStrength',ec.evidence_strength,
          'sourceClassKey',ec.source_class_key,
          'sourceId',ec.source_id,
          'lastVerifiedAt',ec.last_verified_at
        )
        order by
          case ec.lifecycle_state when 'current' then 0 else 1 end,
          ec.last_verified_at desc nulls last,
          ec.id
      ) as claim_payload
      from local_intel.entity_evidence_claims ec
      where ec.entity_id=b.id
        and ec.disclosure_posture in ('public_directory','public_contactable')
        and 'directory_display'=any(ec.permitted_uses)
        and (
          lower(ec.claim_kind)=any(v_claim_kinds)
          or exists(
            select 1
            from local_intel.v_smart_contact_signals_v1 sf
            where sf.evidence_claim_id=ec.id
              and (cardinality(v_signal_keys)=0 or sf.signal_key=any(v_signal_keys))
          )
        )
        and (ec.lifecycle_state='current' or v_include_historical)
    ) claims on true
    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'standing','canonical',
            'personEntityId',pe.id,
            'name',pe.name,
            'relationshipKind',r.relationship_kind,
            'roleTitle',r.role_title,
            'roleFunction',r.role_function,
            'authority',jsonb_strip_nulls(jsonb_build_object(
              'functionalDomain',a.functional_domain,
              'authorityLevel',a.authority_level,
              'decisionDomains',a.decision_domains,
              'organizationalScope',a.organizational_scope,
              'relationshipPower',a.relationship_power,
              'confidence',a.authority_confidence,
              'classificationState',a.classification_state
            )),
            'relationshipConfidence',r.current_confidence,
            'sourceId',r.source_id,
            'lastVerifiedAt',r.last_verified_at
          )
          order by coalesce(a.authority_confidence,0) desc,r.current_confidence desc nulls last,pe.name
        ) as canonical_people,
        count(*)::integer as canonical_count
      from local_intel.entity_relationships r
      join local_intel.entities pe
        on pe.id=r.subject_entity_id
       and pe.entity_type='person'
       and pe.status='active'
      left join local_intel.v_relationship_authority_effective_v1 a
        on a.relationship_id=r.id
      where r.object_entity_id=b.id
        and r.relationship_kind in ('holds_role_at','works_for','primary_contact_for','owns','founded')
        and r.is_current
        and r.truth_state in ('observed','accepted_current')
        and r.conflict_state='none'
    ) people on true
    left join lateral (
      select
        jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'standing','discovery_candidate',
            'candidateId',pdc.id,
            'name',pdc.candidate_name,
            'role',pdc.candidate_role,
            'email',pdc.candidate_email,
            'phone',pdc.candidate_phone,
            'confidence',pdc.confidence,
            'reviewState',pdc.review_state,
            'sourceId',pdc.source_id,
            'rationale',pdc.rationale
          ))
          order by pdc.confidence desc,pdc.candidate_name
        ) as candidate_people,
        count(*)::integer as candidate_count
      from local_intel.person_discovery_candidates pdc
      where pdc.organization_entity_id=b.id
        and pdc.review_state not in ('duplicate','canonicalized')
        and pdc.matched_person_entity_id is null
    ) candidates on true
    left join lateral (
      select
        jsonb_agg(
          jsonb_build_object(
            'contactType',cr.contact_type,
            'contactValue',cr.contact_value,
            'contactPointId',cr.contact_point_id,
            'routeEntityId',cr.route_entity_id,
            'routeEntityName',cr.route_entity_name,
            'routeKind',cr.route_kind,
            'contactScope',cr.contact_scope,
            'verificationState',cr.verification_state,
            'deliverabilityState',cr.deliverability_state,
            'contactability',cr.effective_contactability,
            'lastCheckedAt',cr.last_checked_at,
            'sourceId',cr.source_id
          )
          order by
            case when cr.effective_contactability='direct_contactable' then 0 else 1 end,
            case when cr.verification_state like 'official%current%' then 0 else 1 end,
            cr.contact_type,cr.hierarchy_hops,cr.route_entity_name
        ) as route_payload,
        array_agg(distinct cr.contact_type order by cr.contact_type) as available_types,
        count(*)::integer as route_count,
        bool_or(cr.verification_state in ('official_source_current','official_state_directory_current','multi_source_current')) as has_official_current,
        max(cr.last_checked_at) as latest_contact_checked_at
      from local_intel.v_best_entity_contact_route_v1 cr
      where cr.entity_id=b.id
        and coalesce(cr.effective_contactability,'')<>'blocked'
    ) routes on true
  ),
  filtered as (
    select *
    from candidate_enriched c
    where (
      v_relationship_filter='any'
      or (v_relationship_filter='related' and c.is_related)
      or (v_relationship_filter='unrelated' and not c.is_related)
    )
      and (not v_require_named_person or c.canonical_people_count+c.candidate_people_count>0)
      and (not v_require_contactable or c.route_count>0)
  ),
  scored as (
    select
      c.*,
      (
        case
          when v_text is not null and lower(c.name)=v_text then 30
          when v_text is not null and lower(c.name) like '%'||v_text||'%' then 18
          when v_text is not null then 8
          else 0
        end
        + c.matching_signal_count*14
        + least(c.signal_count,5)*2
        + case
            when c.canonical_people_count>0 then 12
            when c.candidate_people_count>0 then 6
            else 0
          end
        + case when 'decision_contact_known'=any(c.signal_keys) then 10 else 0 end
        + case when c.route_count>0 then 8 else 0 end
        + case when c.has_official_current_route then 5 else 0 end
        + case when c.is_related then 2 else 0 end
      )::integer as relevance_score,
      array(
        select x
        from unnest(v_required_contact_types) x
        where not (x=any(c.available_contact_types))
      ) as missing_required_contact_types
    from filtered c
  ),
  bounded as (
    select *
    from scored
    order by relevance_score desc,name,id
    limit v_limit
  ),
  payloads as (
    select
      b.relevance_score,
      b.name,
      b.id,
      jsonb_build_object(
        'entityId',b.id,
        'name',b.name,
        'entityType',b.entity_type,
        'description',b.description,
        'websiteUrl',b.website_url,
        'geography',jsonb_strip_nulls(jsonb_build_object(
          'addressLine1',b.address_line1,
          'city',b.city,
          'state',b.state,
          'postalCode',b.postal_code
        )),
        'identity',jsonb_build_object(
          'verificationState',b.verification_state,
          'lastVerifiedAt',b.last_verified_at
        ),
        'match',jsonb_build_object(
          'relevanceScore',b.relevance_score,
          'signalKeys',to_jsonb(b.signal_keys),
          'matchingSignalKeys',coalesce((
            select jsonb_agg(x order by x)
            from unnest(b.signal_keys) x
            where x=any(v_signal_keys)
          ),'[]'::jsonb),
          'evidence',b.evidence_payload
        ),
        'people',jsonb_build_object(
          'state',case
            when b.canonical_people_count>0 then 'canonical'
            when b.candidate_people_count>0 then 'candidate_only'
            else 'missing'
          end,
          'canonical',b.canonical_people,
          'candidates',b.candidate_people
        ),
        'contactability',jsonb_build_object(
          'state',case
            when b.route_count=0 then 'missing'
            when b.has_official_current_route then 'verified_current'
            else 'public_observed'
          end,
          'availableTypes',to_jsonb(b.available_contact_types),
          'bestRoutes',b.contact_routes
        ),
        'freshness',jsonb_build_object(
          'state',case
            when b.latest_verified_at='epoch'::timestamptz then 'unknown'
            when b.latest_verified_at >= now()-interval '365 days' then 'current'
            else 'stale'
          end,
          'latestVerifiedAt',nullif(b.latest_verified_at,'epoch'::timestamptz)
        ),
        'researchGaps',to_jsonb(
          array_remove(array[
            case
              when b.canonical_people_count=0 and b.candidate_people_count>0
              then 'person_candidates_need_canonicalization'
            end,
            case
              when b.canonical_people_count+b.candidate_people_count=0
              then 'decision_person_missing'
            end
          ],null)
          || coalesce((
            select array_agg(x||'_missing' order by x)
            from unnest(b.missing_required_contact_types) x
          ),'{}'::text[])
        ),
        'organizationOverlay',atlas.shared_directory_entity_overlay_service_v1(
          p_organization_id,b.id
        )
      ) as payload
    from bounded b
  )
  select
    coalesce(jsonb_agg(payload order by relevance_score desc,name,id),'[]'::jsonb),
    count(*)::integer
  into v_items,v_count
  from payloads;

  return jsonb_build_object(
    'contractVersion','atlas_smart_contacts_v1',
    'productName','Atlas Smart Contacts',
    'organizationId',p_organization_id,
    'query',p_query,
    'resultCount',v_count,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'canonicalReality','Shared Intelligence',
      'organizationMeaning','requesting Organization overlay only',
      'candidatePeopleAreCanonicalTruth',false,
      'searchCreatesRelationship',false,
      'searchAuthorizesCommunication',false
    )
  );
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.smart_contacts_search_self_api_v1(p_organization_id uuid, p_query jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if atlas.current_effective_organization_membership_v1(p_organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return atlas.smart_contacts_search_service_v1(p_organization_id,p_query,p_limit);
end
$function$
;

revoke all on function atlas.smart_contacts_search_service_v1(uuid,jsonb,integer)
  from public,anon,authenticated;
grant execute on function atlas.smart_contacts_search_service_v1(uuid,jsonb,integer)
  to service_role;

revoke all on function atlas.smart_contacts_search_self_api_v1(uuid,jsonb,integer)
  from public,anon;
grant execute on function atlas.smart_contacts_search_self_api_v1(uuid,jsonb,integer)
  to authenticated;

comment on function atlas.smart_contacts_search_service_v1(uuid,jsonb,integer) is
  'Canonical Atlas Smart Contacts read contract. Composes Shared Intelligence identity/evidence/contact routes with exactly one requesting Organization overlay. New product/agent contact discovery should use this contract rather than assembling legacy buyer/outreach/domain tables directly.';

comment on function atlas.smart_contacts_search_self_api_v1(uuid,jsonb,integer) is
  'Authenticated Atlas Smart Contacts read API. Membership-scoped wrapper over the canonical Smart Contacts search contract.';

comment on function atlas.shared_directory_target_search_service_v1(uuid,jsonb,jsonb,text[],integer) is
  'Lower-level Shared Directory search primitive retained beneath Atlas Smart Contacts and contact-set execution. New product/agent contact discovery should prefer atlas.smart_contacts_search_service_v1.';
