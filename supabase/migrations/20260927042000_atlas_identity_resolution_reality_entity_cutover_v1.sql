-- Atlas Identity Resolution -> Reality Entity authority cutover v1.
--
-- Shared Intelligence remains an evidence field. A resolver candidate becomes
-- selectable/committable only when the same entity has been admitted to
-- reality.entities. Learned private bindings and committed resolutions terminate
-- in canonical Reality identity, not in local_intel.entities.
--
-- This is append-only repair over the already-released V1/V2 resolver migrations.
-- It does not migrate Shared Intelligence rows into Reality and does not alter
-- Ledger ownership/custody.

do $block$
declare
  v_missing bigint;
begin
  select count(*) into v_missing
  from (
    select canonical_entity_id as entity_id
    from atlas.ledger_source_party_resolutions

    union all

    select selected_entity_id
    from atlas.ledger_source_party_resolution_cases
    where selected_entity_id is not null

    union all

    select canonical_entity_id
    from atlas.ledger_source_party_resolution_candidates

    union all

    select canonical_entity_id
    from local_intel.entity_private_identifier_bindings

    union all

    select asserted_entity_id
    from local_intel.entity_private_identifier_binding_conflicts
  ) x
  left join reality.entities r on r.id=x.entity_id
  where r.id is null;

  if v_missing<>0 then
    raise exception
      'Reality identity cutover blocked: % resolver entity references are not admitted to reality.entities.',
      v_missing
      using errcode='23503';
  end if;
end
$block$;

-- Drop only the legacy Shared Intelligence foreign keys at this seam.
do $block$
declare
  v_fk record;
begin
  for v_fk in
    select n.nspname as schema_name,c.relname as table_name,con.conname
    from pg_constraint con
    join pg_class c on c.oid=con.conrelid
    join pg_namespace n on n.oid=c.relnamespace
    where con.contype='f'
      and con.confrelid='local_intel.entities'::regclass
      and (
        (n.nspname='atlas' and c.relname in (
          'ledger_source_party_resolutions',
          'ledger_source_party_resolution_cases',
          'ledger_source_party_resolution_candidates'
        ))
        or
        (n.nspname='local_intel' and c.relname in (
          'entity_private_identifier_bindings',
          'entity_private_identifier_binding_conflicts'
        ))
      )
  loop
    execute format(
      'alter table %I.%I drop constraint %I',
      v_fk.schema_name,v_fk.table_name,v_fk.conname
    );
  end loop;
end
$block$;

alter table atlas.ledger_source_party_resolutions
  add constraint ledger_source_party_resolutions_reality_entity_fk_v1
  foreign key (canonical_entity_id)
  references reality.entities(id)
  on delete restrict;

alter table atlas.ledger_source_party_resolution_cases
  add constraint ledger_source_party_resolution_cases_reality_entity_fk_v1
  foreign key (selected_entity_id)
  references reality.entities(id)
  on delete restrict;

alter table atlas.ledger_source_party_resolution_candidates
  add constraint ledger_source_party_resolution_candidates_reality_entity_fk_v1
  foreign key (canonical_entity_id)
  references reality.entities(id)
  on delete restrict;

alter table local_intel.entity_private_identifier_bindings
  add constraint entity_private_identifier_bindings_reality_entity_fk_v1
  foreign key (canonical_entity_id)
  references reality.entities(id)
  on delete restrict;

alter table local_intel.entity_private_identifier_binding_conflicts
  add constraint entity_private_identifier_binding_conflicts_reality_entity_fk_v1
  foreign key (asserted_entity_id)
  references reality.entities(id)
  on delete restrict;

comment on column atlas.ledger_source_party_resolutions.canonical_entity_id is
  'Canonical Reality entity selected for this Ledger-private source record. Shared Intelligence may supply evidence but is not identity authority.';

comment on column atlas.ledger_source_party_resolution_candidates.canonical_entity_id is
  'Reality entity eligible as a candidate. local_intel evidence contributes only after the entity has been admitted to Reality.';

comment on column local_intel.entity_private_identifier_bindings.canonical_entity_id is
  'Canonical Reality entity learned for this resolver-private opaque identifier binding.';

-- V2 still intentionally calls this low-level V1 write service. Keep the service,
-- but correct its canonical authority boundary.
create or replace function atlas.resolve_ledger_source_party_record_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_canonical_entity_id uuid,
  p_resolution_method text,
  p_confidence numeric default 1.0,
  p_resolver_version text default null,
  p_resolution_basis jsonb default '{}'::jsonb,
  p_established_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_method text:=lower(btrim(coalesce(p_resolution_method,'')));
  v_resolution atlas.ledger_source_party_resolutions%rowtype;
begin
  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from reality.entities e
    where e.id=p_canonical_entity_id
      and e.identity_state='canonical'
  ) then
    raise exception 'Canonical Reality entity not found or not canonical.'
      using errcode='P0002';
  end if;

  if v_method !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then
    raise exception 'Resolution method must be normalized.'
      using errcode='22023';
  end if;

  if p_confidence < 0 or p_confidence > 1 then
    raise exception 'Resolution confidence must be between 0 and 1.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_resolution_basis,'{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Resolution basis and metadata must be JSON objects.'
      using errcode='22023';
  end if;

  if p_established_by_principal_id is not null
     and not atlas.principal_has_ledger_authority_v1(
       p_established_by_principal_id,p_ledger_id
     ) then
    raise exception 'Principal lacks authority over Ledger.'
      using errcode='42501';
  end if;

  select *
  into v_resolution
  from atlas.ledger_source_party_resolutions x
  where x.source_party_record_id=p_source_party_record_id
    and x.is_current
  limit 1;

  if v_resolution.id is not null
     and v_resolution.canonical_entity_id=p_canonical_entity_id then
    update atlas.ledger_source_party_resolutions x
    set resolution_method=v_method,
        confidence=p_confidence,
        resolver_version=nullif(btrim(p_resolver_version),''),
        resolution_basis=x.resolution_basis || coalesce(p_resolution_basis,'{}'::jsonb),
        established_by_principal_id=coalesce(
          p_established_by_principal_id,x.established_by_principal_id
        ),
        metadata=x.metadata || coalesce(p_metadata,'{}'::jsonb)
    where x.id=v_resolution.id
    returning * into v_resolution;
  else
    if v_resolution.id is not null then
      update atlas.ledger_source_party_resolutions
      set is_current=false,
          superseded_at=now()
      where id=v_resolution.id;
    end if;

    insert into atlas.ledger_source_party_resolutions(
      ledger_id,source_party_record_id,canonical_entity_id,is_current,
      resolution_method,confidence,resolver_version,resolution_basis,
      established_by_principal_id,metadata
    )
    values(
      p_ledger_id,p_source_party_record_id,p_canonical_entity_id,true,
      v_method,p_confidence,nullif(btrim(p_resolver_version),''),
      coalesce(p_resolution_basis,'{}'::jsonb),
      p_established_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_resolution;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_v1',
    'resolutionId',v_resolution.id,
    'ledgerId',v_resolution.ledger_id,
    'sourcePartyRecordId',v_resolution.source_party_record_id,
    'canonicalEntityId',v_resolution.canonical_entity_id,
    'resolutionMethod',v_resolution.resolution_method,
    'confidence',v_resolution.confidence,
    'isCurrent',v_resolution.is_current
  );
end
$function$;

-- Preserve the existing read contract while sourcing identity from Reality.
create or replace function atlas.ledger_source_party_record_detail_service_v1(
  p_ledger_id uuid,
  p_source_party_record_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','ledger_source_party_record_detail_v1',
    'ledgerId',r.ledger_id,
    'sourcePartyRecord',jsonb_build_object(
      'sourcePartyRecordId',r.id,
      'sourceConnectionId',r.source_connection_id,
      'providerKey',c.provider_key,
      'providerRecordType',r.provider_record_type,
      'providerRecordId',r.provider_record_id,
      'displayName',r.display_name,
      'sourceRecordState',r.source_record_state,
      'sourcePayload',r.source_payload,
      'payloadHash',r.payload_hash,
      'observedAt',r.observed_at,
      'sourceUpdatedAt',r.source_updated_at,
      'metadata',r.metadata
    ),
    'currentResolution',case
      when x.id is null then null
      else jsonb_build_object(
        'resolutionId',x.id,
        'canonicalEntityId',x.canonical_entity_id,
        'resolutionMethod',x.resolution_method,
        'confidence',x.confidence,
        'resolverVersion',x.resolver_version,
        'resolutionBasis',x.resolution_basis,
        'establishedAt',x.established_at,
        'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
          'entityId',e.id,
          'name',e.display_name,
          'displayName',e.display_name,
          'entityType',e.entity_kind,
          'entityKind',e.entity_kind,
          'identityState',e.identity_state,
          'city',e.metadata#>>'{physicalAddress,city}',
          'state',e.metadata#>>'{physicalAddress,state}'
        ))
      )
    end
  )
  from atlas.ledger_source_party_records r
  join atlas.ledger_source_connections c
    on c.id=r.source_connection_id
   and c.ledger_id=r.ledger_id
  left join atlas.ledger_source_party_resolutions x
    on x.source_party_record_id=r.id
   and x.ledger_id=r.ledger_id
   and x.is_current
  left join reality.entities e
    on e.id=x.canonical_entity_id
  where r.id=p_source_party_record_id
    and r.ledger_id=p_ledger_id;
$function$;

-- V2 private binding projection keeps private resolver state in local_intel,
-- but canonical_entity_id now carries Reality identity.
create or replace function atlas.refresh_private_identifier_bindings_for_source_record_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_resolution atlas.ledger_source_party_resolutions%rowtype;
  v_signal record;
  v_existing local_intel.entity_private_identifier_bindings%rowtype;
  v_semantic atlas.identity_identifier_semantics%rowtype;
begin
  select * into v_resolution
  from atlas.ledger_source_party_resolutions r
  where r.ledger_id=p_ledger_id
    and r.source_party_record_id=p_source_party_record_id
    and r.is_current
  limit 1;

  if v_resolution.id is null then
    return;
  end if;

  for v_signal in
    select
      s.identifier_kind,s.semantic_key,s.token_version,s.blind_token,
      s.valid_from,s.valid_until
    from atlas.ledger_source_party_identity_signals s
    where s.ledger_id=p_ledger_id
      and s.source_party_record_id=p_source_party_record_id
      and s.signal_state='current'
      and s.signal_mode='private_blind_match'
  loop
    select * into v_semantic
    from atlas.identity_identifier_semantics m
    where m.semantic_key=v_signal.semantic_key
      and m.semantic_state='active';

    if v_semantic.semantic_key is null
       or not v_semantic.teaches_private_binding then
      continue;
    end if;

    if not exists(
      select 1
      from reality.entities e
      where e.id=v_resolution.canonical_entity_id
        and e.identity_state='canonical'
        and e.entity_kind=any(v_semantic.allowed_entity_types)
    ) then
      continue;
    end if;

    v_existing:=null;

    if v_semantic.cardinality_mode='exclusive' then
      select b.* into v_existing
      from local_intel.entity_private_identifier_bindings b
      where b.identifier_kind=v_signal.identifier_kind
        and b.token_version=v_signal.token_version
        and b.blind_token=v_signal.blind_token
        and b.binding_state='current'
        and b.canonical_entity_id<>v_resolution.canonical_entity_id
        and (b.valid_until is null or b.valid_until >= v_signal.valid_from)
        and (v_signal.valid_until is null or v_signal.valid_until >= b.valid_from)
      order by b.first_confirmed_at
      limit 1;

      if v_existing.id is not null then
        insert into local_intel.entity_private_identifier_binding_conflicts(
          existing_binding_id,asserted_entity_id,metadata
        )
        values(
          v_existing.id,v_resolution.canonical_entity_id,
          jsonb_build_object(
            'basis','exclusive_identifier_overlap',
            'sourcePartyRecordId',p_source_party_record_id
          )
        )
        on conflict (existing_binding_id,asserted_entity_id)
          where conflict_state='open'
        do update set
          last_observed_at=now(),
          updated_at=now();
        continue;
      end if;
    end if;

    insert into local_intel.entity_private_identifier_bindings(
      canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,
      binding_state,valid_from,valid_until,metadata
    )
    values(
      v_resolution.canonical_entity_id,
      v_signal.identifier_kind,
      v_signal.semantic_key,
      v_signal.token_version,
      v_signal.blind_token,
      'current',
      v_signal.valid_from,
      v_signal.valid_until,
      jsonb_build_object(
        'basis','confirmed_source_party_resolution_v2'
      )
    )
    on conflict (
      canonical_entity_id,identifier_kind,semantic_key,token_version,blind_token,valid_from
    ) where binding_state='current'
    do update set
      valid_until=excluded.valid_until,
      last_confirmed_at=now(),
      metadata=local_intel.entity_private_identifier_bindings.metadata
        || excluded.metadata,
      updated_at=now();
  end loop;
end
$function$;

-- Shared Intelligence supplies evidence; Reality admission gates candidacy.
create or replace function atlas.evaluate_ledger_source_party_resolution_service_v2(
  p_ledger_id uuid,
  p_source_party_record_id uuid,
  p_as_of_date date default current_date,
  p_policy_key text default 'default_v1',
  p_resolver_version text default 'identity_resolution_engine_v2'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_policy atlas.identity_resolution_policies%rowtype;
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_existing atlas.ledger_source_party_resolutions%rowtype;
  v_top numeric(5,4);
  v_second numeric(5,4);
  v_top_auto_eligible boolean;
  v_state text;
  v_candidates jsonb;
begin
  if p_as_of_date is null then
    raise exception 'Resolution as-of date is required.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.ledger_source_party_records r
    where r.id=p_source_party_record_id
      and r.ledger_id=p_ledger_id
      and r.source_record_state='current'
  ) then
    raise exception 'Current source party record is outside Ledger or missing.'
      using errcode='42501';
  end if;

  select * into v_existing
  from atlas.ledger_source_party_resolutions x
  where x.ledger_id=p_ledger_id
    and x.source_party_record_id=p_source_party_record_id
    and x.is_current
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'contractVersion','ledger_source_party_resolution_evaluation_v2',
      'decisionState','already_resolved',
      'sourcePartyRecordId',p_source_party_record_id,
      'canonicalEntityId',v_existing.canonical_entity_id,
      'resolutionId',v_existing.id
    );
  end if;

  select * into v_policy
  from atlas.identity_resolution_policies p
  where p.policy_key=p_policy_key
    and p.policy_state='active';

  if v_policy.policy_key is null then
    raise exception 'Identity resolution policy is missing or inactive.'
      using errcode='P0002';
  end if;

  update atlas.ledger_source_party_resolution_cases c
  set case_state='superseded',
      updated_at=now()
  where c.ledger_id=p_ledger_id
    and c.source_party_record_id=p_source_party_record_id
    and c.case_state in ('auto_resolvable','needs_review','new_candidate');

  create temporary table if not exists pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id uuid,
    identity_signal_id uuid,
    identifier_kind text,
    signal_mode text,
    semantic_key text,
    evidence_family_key text,
    weight numeric(5,4),
    allows_auto_resolution boolean
  ) on commit drop;
  truncate pg_temp.atlas_resolution_matches_v2;

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    re.id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.shared_evidence_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.shared_evidence_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_evidence_claims e
    on e.claim_kind=s.identifier_kind
   and e.normalized_value=s.normalized_value
   and e.lifecycle_state='current'
   and e.disclosure_posture<>'suppressed'
   and 'identity_resolution'=any(e.permitted_uses)
   and (e.valid_from is null or e.valid_from<=p_as_of_date)
   and (e.valid_until is null or e.valid_until>=p_as_of_date)
  join reality.entities re
    on re.id=e.entity_id
   and re.identity_state='canonical'
   and re.entity_kind=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='shared_evidence_lookup'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date)
    and not exists(
      select 1
      from local_intel.entity_contact_suppressions sup
      where sup.entity_id=e.entity_id
        and sup.suppression_state='active'
        and (sup.effective_until is null or sup.effective_until>now())
        and sup.suppression_scope='all_use'
        and (sup.evidence_claim_id is null or sup.evidence_claim_id=e.id)
    );

  insert into pg_temp.atlas_resolution_matches_v2(
    canonical_entity_id,identity_signal_id,identifier_kind,signal_mode,
    semantic_key,evidence_family_key,weight,allows_auto_resolution
  )
  select distinct
    re.id,
    s.id,
    s.identifier_kind,
    s.signal_mode,
    s.semantic_key,
    s.evidence_family_key,
    sp.private_blind_weight,
    sem.allows_auto_resolution
  from atlas.ledger_source_party_identity_signals s
  join atlas.identity_resolution_signal_policies sp
    on sp.identifier_kind=s.identifier_kind
   and sp.signal_state='active'
   and sp.private_blind_weight is not null
  join atlas.identity_identifier_semantics sem
    on sem.semantic_key=s.semantic_key
   and sem.semantic_state='active'
   and sem.allows_resolution
  join local_intel.entity_private_identifier_bindings b
    on b.identifier_kind=s.identifier_kind
   and b.token_version=s.token_version
   and b.blind_token=s.blind_token
   and b.binding_state='current'
   and b.valid_from<=p_as_of_date
   and (b.valid_until is null or b.valid_until>=p_as_of_date)
  join reality.entities re
    on re.id=b.canonical_entity_id
   and re.identity_state='canonical'
   and re.entity_kind=any(sem.allowed_entity_types)
  where s.ledger_id=p_ledger_id
    and s.source_party_record_id=p_source_party_record_id
    and s.signal_state='current'
    and s.signal_mode='private_blind_match'
    and s.valid_from<=p_as_of_date
    and (s.valid_until is null or s.valid_until>=p_as_of_date);

  insert into atlas.ledger_source_party_resolution_cases(
    ledger_id,source_party_record_id,policy_key,resolver_version,
    case_state,decision_basis
  )
  values(
    p_ledger_id,p_source_party_record_id,v_policy.policy_key,
    coalesce(nullif(btrim(p_resolver_version),''),'identity_resolution_engine_v2'),
    'new_candidate',
    jsonb_build_object(
      'asOfDate',p_as_of_date,
      'autoResolveThreshold',v_policy.auto_resolve_threshold,
      'reviewThreshold',v_policy.review_threshold,
      'ambiguityMargin',v_policy.ambiguity_margin,
      'scoring','strongest_signal_per_evidence_family_then_probabilistic_union',
      'canonicalAuthority','reality.entities'
    )
  )
  returning * into v_case;

  with family_matches as(
    select
      canonical_entity_id,
      evidence_family_key,
      max(weight) as family_weight,
      bool_or(allows_auto_resolution) as family_auto_eligible,
      jsonb_agg(
        distinct jsonb_build_object(
          'identifierKind',identifier_kind,
          'signalMode',signal_mode,
          'semanticKey',semantic_key
        )
      ) as family_signals
    from pg_temp.atlas_resolution_matches_v2
    group by canonical_entity_id,evidence_family_key
  ),
  scored as(
    select
      canonical_entity_id,
      case
        when bool_or(family_weight>=0.9999) then 1.0000::numeric
        else round(
          (1-exp(sum(ln(greatest(1-family_weight,0.000001)))))::numeric,
          4
        )
      end as score,
      bool_or(family_auto_eligible) as auto_eligible,
      jsonb_agg(
        jsonb_build_object(
          'evidenceFamilyKey',evidence_family_key,
          'familyWeight',family_weight,
          'signals',family_signals
        )
        order by family_weight desc,evidence_family_key
      ) as summary
    from family_matches
    group by canonical_entity_id
  ),
  ranked as(
    select
      canonical_entity_id,
      least(score,1.0000)::numeric(5,4) as score,
      auto_eligible,
      summary,
      row_number() over(order by score desc,canonical_entity_id) as rank_no
    from scored
  )
  insert into atlas.ledger_source_party_resolution_candidates(
    ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,score,match_summary
  )
  select
    p_ledger_id,v_case.id,canonical_entity_id,rank_no,score,
    jsonb_build_object(
      'autoEligible',auto_eligible,
      'families',summary
    )
  from ranked;

  select
    c.score,
    coalesce((c.match_summary->>'autoEligible')::boolean,false)
  into v_top,v_top_auto_eligible
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=1;

  select c.score into v_second
  from atlas.ledger_source_party_resolution_candidates c
  where c.resolution_case_id=v_case.id
    and c.candidate_rank=2;

  if v_top is null then
    v_state:='new_candidate';
  elsif v_top>=v_policy.auto_resolve_threshold
        and coalesce(v_top_auto_eligible,false)
        and (v_second is null or v_top-v_second>=v_policy.ambiguity_margin) then
    v_state:='auto_resolvable';
  elsif v_top>=v_policy.review_threshold then
    v_state:='needs_review';
  else
    v_state:='new_candidate';
  end if;

  update atlas.ledger_source_party_resolution_cases
  set case_state=v_state,
      top_score=v_top,
      second_score=v_second,
      updated_at=now()
  where id=v_case.id
  returning * into v_case;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'canonicalEntityId',c.canonical_entity_id,
      'candidateRank',c.candidate_rank,
      'score',c.score,
      'matchSummary',c.match_summary,
      'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
        'entityId',e.id,
        'name',e.display_name,
        'displayName',e.display_name,
        'entityType',e.entity_kind,
        'entityKind',e.entity_kind,
        'identityState',e.identity_state,
        'city',e.metadata#>>'{physicalAddress,city}',
        'state',e.metadata#>>'{physicalAddress,state}'
      ))
    )
    order by c.candidate_rank
  ),'[]'::jsonb)
  into v_candidates
  from atlas.ledger_source_party_resolution_candidates c
  join reality.entities e on e.id=c.canonical_entity_id
  where c.resolution_case_id=v_case.id;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_evaluation_v2',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',p_source_party_record_id,
    'asOfDate',p_as_of_date,
    'decisionState',v_case.case_state,
    'topScore',v_case.top_score,
    'secondScore',v_case.second_score,
    'candidates',v_candidates
  );
end
$function$;

create or replace function atlas.commit_ledger_source_party_resolution_case_service_v2(
  p_ledger_id uuid,
  p_resolution_case_id uuid,
  p_canonical_entity_id uuid,
  p_decision_method text default 'human_confirmed',
  p_established_by_principal_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_case atlas.ledger_source_party_resolution_cases%rowtype;
  v_candidate atlas.ledger_source_party_resolution_candidates%rowtype;
  v_method text:=lower(btrim(coalesce(p_decision_method,'')));
  v_resolution jsonb;
  v_resolution_confidence numeric(5,4);
  v_next_rank integer;
begin
  select * into v_case
  from atlas.ledger_source_party_resolution_cases c
  where c.id=p_resolution_case_id
    and c.ledger_id=p_ledger_id;

  if v_case.id is null then
    raise exception 'Resolution case is outside Ledger or missing.'
      using errcode='42501';
  end if;

  if v_method='automatic' then
    if v_case.case_state<>'auto_resolvable' then
      raise exception 'Automatic commit requires an auto-resolvable case.'
        using errcode='22023';
    end if;

    select * into v_candidate
    from atlas.ledger_source_party_resolution_candidates c
    where c.resolution_case_id=v_case.id
      and c.canonical_entity_id=p_canonical_entity_id
      and c.candidate_rank=1;

    if v_candidate.id is null then
      raise exception 'Automatic commit requires the top candidate.'
        using errcode='22023';
    end if;

    v_resolution_confidence:=v_candidate.score;

  elsif v_method='human_confirmed' then
    if v_case.case_state not in ('auto_resolvable','needs_review','new_candidate') then
      raise exception 'Resolution case is not open for human confirmation.'
        using errcode='22023';
    end if;

    if not exists(
      select 1
      from reality.entities e
      where e.id=p_canonical_entity_id
        and e.identity_state='canonical'
    ) then
      raise exception 'Human-confirmed canonical Reality entity does not exist or is not canonical.'
        using errcode='P0002';
    end if;

    select * into v_candidate
    from atlas.ledger_source_party_resolution_candidates c
    where c.resolution_case_id=v_case.id
      and c.canonical_entity_id=p_canonical_entity_id;

    if v_candidate.id is null then
      select coalesce(max(candidate_rank),0)+1
      into v_next_rank
      from atlas.ledger_source_party_resolution_candidates
      where resolution_case_id=v_case.id;

      insert into atlas.ledger_source_party_resolution_candidates(
        ledger_id,resolution_case_id,canonical_entity_id,candidate_rank,
        score,match_summary,candidate_state
      )
      values(
        p_ledger_id,v_case.id,p_canonical_entity_id,v_next_rank,
        0.0000,
        jsonb_build_object(
          'autoEligible',false,
          'families',jsonb_build_array(jsonb_build_object(
            'evidenceFamilyKey','human_confirmation',
            'familyWeight',0.0000,
            'signals',jsonb_build_array(jsonb_build_object(
              'signalMode','human_confirmation',
              'identifierKind','human_confirmation',
              'semanticKey','human_confirmation'
            ))
          ))
        ),
        'proposed'
      )
      returning * into v_candidate;
    end if;

    v_resolution_confidence:=1.0000;
  else
    raise exception 'Decision method must be automatic or human_confirmed.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' then
    raise exception 'Commit metadata must be a JSON object.'
      using errcode='22023';
  end if;

  v_resolution:=atlas.resolve_ledger_source_party_record_service_v1(
    p_ledger_id,
    v_case.source_party_record_id,
    p_canonical_entity_id,
    v_method,
    v_resolution_confidence,
    v_case.resolver_version,
    v_case.decision_basis || jsonb_build_object(
      'resolutionCaseId',v_case.id,
      'candidateRank',v_candidate.candidate_rank,
      'machineCandidateScore',v_candidate.score,
      'matchSummary',v_candidate.match_summary,
      'semanticResolutionVersion','v2',
      'canonicalAuthority','reality.entities'
    ),
    p_established_by_principal_id,
    coalesce(p_metadata,'{}'::jsonb)
  );

  update atlas.ledger_source_party_resolution_candidates
  set candidate_state=case
    when canonical_entity_id=p_canonical_entity_id then 'selected'
    else 'rejected'
  end
  where resolution_case_id=v_case.id;

  update atlas.ledger_source_party_resolution_cases
  set case_state='resolved',
      selected_entity_id=p_canonical_entity_id,
      decided_at=now(),
      decided_by_principal_id=p_established_by_principal_id,
      metadata=metadata || coalesce(p_metadata,'{}'::jsonb),
      updated_at=now()
  where id=v_case.id;

  return jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_commit_v2',
    'resolutionCaseId',v_case.id,
    'sourcePartyRecordId',v_case.source_party_record_id,
    'canonicalEntityId',p_canonical_entity_id,
    'decisionMethod',v_method,
    'resolution',v_resolution
  );
end
$function$;

-- Preserve read compatibility for case detail while presenting canonical Reality.
create or replace function atlas.ledger_source_party_resolution_case_detail_service_v1(
  p_ledger_id uuid,
  p_resolution_case_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
  select jsonb_build_object(
    'contractVersion','ledger_source_party_resolution_case_detail_v1',
    'resolutionCaseId',c.id,
    'sourcePartyRecordId',c.source_party_record_id,
    'caseState',c.case_state,
    'policyKey',c.policy_key,
    'resolverVersion',c.resolver_version,
    'topScore',c.top_score,
    'secondScore',c.second_score,
    'selectedEntityId',c.selected_entity_id,
    'evaluatedAt',c.evaluated_at,
    'decidedAt',c.decided_at,
    'candidates',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'canonicalEntityId',x.canonical_entity_id,
          'candidateRank',x.candidate_rank,
          'score',x.score,
          'candidateState',x.candidate_state,
          'matchSummary',x.match_summary,
          'canonicalEntity',jsonb_strip_nulls(jsonb_build_object(
            'entityId',e.id,
            'name',e.display_name,
            'displayName',e.display_name,
            'entityType',e.entity_kind,
            'entityKind',e.entity_kind,
            'identityState',e.identity_state,
            'city',e.metadata#>>'{physicalAddress,city}',
            'state',e.metadata#>>'{physicalAddress,state}'
          ))
        )
        order by x.candidate_rank
      )
      from atlas.ledger_source_party_resolution_candidates x
      join reality.entities e on e.id=x.canonical_entity_id
      where x.resolution_case_id=c.id
        and x.ledger_id=c.ledger_id
    ),'[]'::jsonb)
  )
  from atlas.ledger_source_party_resolution_cases c
  where c.id=p_resolution_case_id
    and c.ledger_id=p_ledger_id;
$function$;

-- V2 is the governed identity-resolution path. V1 mutation/evaluation entry
-- points are retired so they cannot bypass semantic/cardinality/temporal rules.
revoke execute on function atlas.upsert_ledger_source_party_identity_signal_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,timestamptz
) from service_role;

revoke execute on function atlas.evaluate_ledger_source_party_resolution_service_v1(
  uuid,uuid,text,text
) from service_role;

revoke execute on function atlas.commit_ledger_source_party_resolution_case_service_v1(
  uuid,uuid,uuid,text,uuid,jsonb
) from service_role;

comment on function atlas.upsert_ledger_source_party_identity_signal_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb,jsonb,timestamptz
) is
  'Legacy V1 signal write surface. Execution retired after semantic/cardinality/temporal V2 became governing resolver path.';

comment on function atlas.evaluate_ledger_source_party_resolution_service_v1(
  uuid,uuid,text,text
) is
  'Legacy V1 evaluator. Execution retired; V2 is the governed resolver and canonical identity terminates in reality.entities.';

comment on function atlas.commit_ledger_source_party_resolution_case_service_v1(
  uuid,uuid,uuid,text,uuid,jsonb
) is
  'Legacy V1 commit surface. Execution retired; V2 is the governed resolver and canonical identity terminates in reality.entities.';

comment on function atlas.resolve_ledger_source_party_record_service_v1(
  uuid,uuid,uuid,text,numeric,text,jsonb,uuid,jsonb
) is
  'Low-level resolver write service retained for V2 compatibility. canonical_entity_id must identify a canonical reality.entities row.';

comment on function atlas.evaluate_ledger_source_party_resolution_service_v2(
  uuid,uuid,date,text,text
) is
  'Semantic/cardinality/temporal identity evaluator. Shared Intelligence is evidence; only canonical reality.entities rows may become resolution candidates.';

comment on function atlas.commit_ledger_source_party_resolution_case_service_v2(
  uuid,uuid,uuid,text,uuid,jsonb
) is
  'Governed V2 resolution commit. Human and automatic commits terminate in canonical reality.entities identity; private bindings remain resolver-private evidence.';
