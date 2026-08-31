-- Atlas Person Life Timeline Projection v1
--
-- Read-only personal Journal/thread projection over canonical person-owned truth.
-- This migration creates no Journal storage and no new writer. Evidence, claims,
-- Life definitions, definition revisions, and Life state events remain canonical.
--
-- Timeline order is Atlas learned/recorded time. World/observation/effective time
-- remains separately visible on each source event so projection order never
-- rewrites source chronology.

begin;

create or replace function atlas.person_life_timeline_self_api_v1(
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_limit integer;
  v_entries jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_limit := coalesce(p_limit,200);
  if v_limit < 1 or v_limit > 500 then
    raise exception 'p_limit must be between 1 and 500.' using errcode='22023';
  end if;

  with timeline_source as (
    -- Source-custodied evidence. Claims are nested rather than projected as a
    -- second peer event, so one capture remains one Journal/timeline moment while
    -- claim lifecycle and correction history remain visible on that evidence.
    select
      e.learned_at as learned_at,
      e.id as stable_id,
      jsonb_strip_nulls(jsonb_build_object(
        'entryVersion','person_life_timeline_entry_v1',
        'entryKind','evidence_capture',
        'entryId','evidence:'||e.id::text,
        'threadKey',concat_ws(':',e.subject_domain,e.subject_kind,e.subject_id),
        'subject',jsonb_build_object(
          'domain',e.subject_domain,
          'kind',e.subject_kind,
          'id',e.subject_id
        ),
        'learnedAt',e.learned_at,
        'observedAt',e.observed_at,
        'effectiveFrom',e.effective_from,
        'effectiveUntil',e.effective_until,
        'source',jsonb_build_object(
          'canonicalTable','atlas.evidence_records',
          'canonicalId',e.id,
          'sourceKind',e.source_kind,
          'sourceKey',e.source_key,
          'actorUserId',e.actor_user_id
        ),
        'evidence',jsonb_strip_nulls(jsonb_build_object(
          'evidenceId',e.id,
          'evidenceKind',e.evidence_kind,
          'value',e.value,
          'confidence',e.confidence,
          'provenance',e.provenance,
          'metadata',e.metadata
        )),
        'claims',coalesce((
          select jsonb_agg(
            jsonb_strip_nulls(jsonb_build_object(
              'claimId',c.id,
              'claimType',c.claim_type,
              'lifecycleState',c.lifecycle_state,
              'authorityKind',c.authority_kind,
              'value',c.value,
              'confidence',c.confidence,
              'primaryEvidenceId',c.primary_evidence_id,
              'supersedesClaimId',c.supersedes_claim_id,
              'validFrom',c.valid_from,
              'validUntil',c.valid_until,
              'recordedAt',c.recorded_at,
              'supersededAt',c.superseded_at,
              'metadata',c.metadata,
              'evidenceRelations',coalesce((
                select jsonb_agg(jsonb_build_object(
                  'relationKind',l.relation_kind,
                  'metadata',l.metadata
                ) order by l.created_at,l.id)
                from atlas.claim_evidence_links l
                where l.claim_id=c.id and l.evidence_id=e.id
              ),'[]'::jsonb)
            )) order by c.recorded_at,c.id
          )
          from atlas.claim_records c
          where c.scope_kind='person'
            and c.scope_id=v_user_id
            and (
              c.primary_evidence_id=e.id
              or exists (
                select 1 from atlas.claim_evidence_links l
                where l.claim_id=c.id and l.evidence_id=e.id
              )
            )
        ),'[]'::jsonb)
      )) as entry
    from atlas.evidence_records e
    where e.scope_kind='person' and e.scope_id=v_user_id

    union all

    -- Immutable person Life definitions. Current lifecycle status is labeled as
    -- current rather than pretending it was the status at creation time.
    select
      d.created_at as learned_at,
      d.id as stable_id,
      jsonb_strip_nulls(jsonb_build_object(
        'entryVersion','person_life_timeline_entry_v1',
        'entryKind','life_definition_created',
        'entryId','life-definition:'||d.id::text,
        'threadKey',concat_ws(':',d.subject_domain,d.subject_kind,d.subject_id),
        'subject',jsonb_build_object(
          'domain',d.subject_domain,
          'kind',d.subject_kind,
          'id',d.subject_id
        ),
        'learnedAt',d.created_at,
        'source',jsonb_build_object(
          'canonicalTable','atlas.person_life_definitions',
          'canonicalId',d.id,
          'sourceKey',d.source_key,
          'sourceSubject',jsonb_build_object(
            'domain',d.source_domain,
            'kind',d.source_kind,
            'id',d.source_id
          )
        ),
        'definition',jsonb_strip_nulls(jsonb_build_object(
          'definitionId',d.id,
          'signalKind',d.signal_kind,
          'currentStatus',d.status,
          'retiredAt',d.retired_at,
          'lifeSignal',d.life_signal,
          'enginePacket',d.engine_packet,
          'metadata',d.metadata
        ))
      )) as entry
    from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id

    union all

    -- Definition revision receipt. The revised definition supplies the stable
    -- Goal subject/thread; the authorization claim/evidence remain references to
    -- their own canonical records and therefore also appear in evidence history.
    select
      r.created_at as learned_at,
      r.id as stable_id,
      jsonb_strip_nulls(jsonb_build_object(
        'entryVersion','person_life_timeline_entry_v1',
        'entryKind','life_definition_revised',
        'entryId','life-revision:'||r.id::text,
        'threadKey',concat_ws(':',d.subject_domain,d.subject_kind,d.subject_id),
        'subject',jsonb_build_object(
          'domain',d.subject_domain,
          'kind',d.subject_kind,
          'id',d.subject_id
        ),
        'learnedAt',r.created_at,
        'source',jsonb_build_object(
          'canonicalTable','atlas.person_life_definition_revisions',
          'canonicalId',r.id,
          'sourceKey',r.source_key
        ),
        'revision',jsonb_build_object(
          'revisionId',r.id,
          'previousDefinitionId',r.previous_definition_id,
          'revisedDefinitionId',r.revised_definition_id,
          'authorizationClaimId',r.authorization_claim_id,
          'authorizationEvidenceId',r.authorization_evidence_id,
          'requirementKey',r.requirement_key,
          'claimedRequirement',r.claimed_requirement,
          'appliedRequirement',r.applied_requirement,
          'authorizationBasis',r.authorization_basis,
          'authorizationReason',r.authorization_reason
        )
      )) as entry
    from atlas.person_life_definition_revisions r
    join atlas.person_life_definitions d
      on d.id=r.revised_definition_id
     and d.owner_user_id=r.owner_user_id
    where r.owner_user_id=v_user_id

    union all

    -- Evaluations/satisfactions/resolutions already persisted by the generic
    -- person Life state machinery. occurredAt remains separate from createdAt.
    select
      s.created_at as learned_at,
      s.id as stable_id,
      jsonb_strip_nulls(jsonb_build_object(
        'entryVersion','person_life_timeline_entry_v1',
        'entryKind','life_state_event',
        'entryId','life-state-event:'||s.id::text,
        'threadKey',concat_ws(':',d.subject_domain,d.subject_kind,d.subject_id),
        'subject',jsonb_build_object(
          'domain',d.subject_domain,
          'kind',d.subject_kind,
          'id',d.subject_id
        ),
        'learnedAt',s.created_at,
        'occurredAt',s.occurred_at,
        'source',jsonb_build_object(
          'canonicalTable','atlas.person_life_state_events',
          'canonicalId',s.id,
          'sourceKey',s.source_key,
          'definitionId',s.definition_id
        ),
        'stateEvent',jsonb_build_object(
          'eventId',s.id,
          'eventKind',s.event_kind,
          'definitionId',s.definition_id,
          'inputPayload',s.input_payload,
          'evidence',s.evidence,
          'evaluation',s.evaluation
        )
      )) as entry
    from atlas.person_life_state_events s
    join atlas.person_life_definitions d
      on d.id=s.definition_id
     and d.owner_user_id=s.owner_user_id
    where s.owner_user_id=v_user_id
  ), limited as (
    select learned_at,stable_id,entry
    from timeline_source
    order by learned_at desc,stable_id desc
    limit v_limit
  )
  select coalesce(jsonb_agg(entry order by learned_at desc,stable_id desc),'[]'::jsonb)
  into v_entries
  from limited;

  return jsonb_build_object(
    'ok',true,
    'schemaVersion','person_life_timeline_v1',
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'order','learned_at_desc',
    'limit',v_limit,
    'entries',v_entries,
    'truthBoundary',jsonb_build_object(
      'readOnlyProjection',true,
      'journalHasNoIndependentTruth',true,
      'sourceRecordsRemainCanonical',true,
      'claimsRemainBoundToEvidence',true,
      'correctionHistoryRemainsVisible',true,
      'observedAndEffectiveTimeRemainSeparateFromLearnedTime',true,
      'threadKeyGroupsByCanonicalSubjectIdentity',true,
      'doesNotCreateEvidence',true,
      'doesNotCreateClaim',true,
      'doesNotCreateTask',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateConsequence',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.person_life_timeline_self_api_v1(integer) is
  'Read-only signed-in personal Journal/thread projection over canonical Claim/Evidence and person Life definition/revision/state truth. It preserves source chronology and correction history and owns no independent truth.';

revoke all on function atlas.person_life_timeline_self_api_v1(integer) from public, anon;
grant execute on function atlas.person_life_timeline_self_api_v1(integer) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values (
  'atlas.person_life_timeline_self_api_v1(integer)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Project the signed-in human personal Journal/thread timeline from canonical person Claim/Evidence and Life definition/revision/state records.',
    'authorizationBoundary','SECURITY DEFINER fixes every source query to auth.uid(); no caller-supplied person identity is accepted. The endpoint is read-only and grants no mutation, sharing, task, carrier, consequence, or Clock authority.',
    'truthBoundary','The timeline owns no independent truth. Evidence, claims, definitions, revision receipts, and state events remain canonical. Learned time orders the projection while observed/effective/occurred time remains explicitly separate.',
    'directSignedInEndpoint',true
  ),now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after person Life timeline projection registration.';
  end if;
end
$$;

commit;
