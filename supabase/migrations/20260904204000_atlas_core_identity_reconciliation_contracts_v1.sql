-- Atlas Core identity reconciliation guarded contracts v1
-- Reality Foundation #788
--
-- Adds read/review surfaces over the evidence-first identity foundation.
-- Ordinary source ingestion remains #789 Atlas Receive work.

alter table atlas.identity_reconciliation_adjudications
  drop constraint if exists identity_reconciliation_adjudications_decision_kind_check;

alter table atlas.identity_reconciliation_adjudications
  add constraint identity_reconciliation_adjudications_decision_kind_check
  check (decision_kind in (
    'accept_source_binding',
    'reject_source_binding',
    'subjects_equivalent',
    'subjects_distinct',
    'accept_claim',
    'reject_claim',
    'split_correction',
    'reject_split_correction',
    'defer_unresolved',
    'supersede_prior',
    'other'
  ));

create or replace function atlas.require_identity_steward_v1(p_organization_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_membership atlas.organization_memberships%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_membership
  from atlas.organization_memberships om
  where om.organization_id=p_organization_id
    and om.user_id=auth.uid()
    and om.active=true
  order by case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end, om.created_at
  limit 1;

  if v_membership.id is null or v_membership.role not in ('owner','consultant') then
    raise exception 'Identity stewardship requires Owner or Consultant authority.' using errcode='42501';
  end if;

  return v_membership.id;
end;
$function$;

create or replace function atlas.identity_party_projection_v1(p_subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_subject atlas.identity_subjects%rowtype;
  v_projection atlas.identity_subject_projections%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  select * into v_subject
  from atlas.identity_subjects
  where id=p_subject_id;

  if v_subject.id is null then
    raise exception 'Identity subject not found.' using errcode='P0002';
  end if;

  if not atlas.is_organization_member(v_subject.organization_id) then
    raise exception 'Identity subject is outside your organization.' using errcode='42501';
  end if;

  select * into v_projection
  from atlas.identity_subject_projections
  where subject_id=v_subject.id;

  return jsonb_build_object(
    'contractVersion','identity_party_projection_v1',
    'subjectId',v_subject.id,
    'organizationId',v_subject.organization_id,
    'subjectState',v_subject.state,
    'partyKind',coalesce(v_projection.subject_kind,'unknown'),
    'displayName',v_projection.display_name,
    'aliases',coalesce(v_projection.aliases,'[]'::jsonb),
    'contactPoints',coalesce(v_projection.contact_points,'[]'::jsonb),
    'unresolvedIdentity',coalesce(v_projection.unresolved_identity,true),
    'confidence',v_projection.confidence,
    'projectionBasis',coalesce(v_projection.projection_basis,'{}'::jsonb),
    'projectionUpdatedAt',v_projection.updated_at
  );
end;
$function$;

create or replace function atlas.identity_subject_provenance_v1(p_subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_subject atlas.identity_subjects%rowtype;
  v_membership_id uuid;
  v_claims jsonb;
  v_source_bindings jsonb;
  v_pair_assertions jsonb;
  v_adjudications jsonb;
  v_reviews jsonb;
begin
  select * into v_subject
  from atlas.identity_subjects
  where id=p_subject_id;

  if v_subject.id is null then
    raise exception 'Identity subject not found.' using errcode='P0002';
  end if;

  v_membership_id := atlas.require_identity_steward_v1(v_subject.organization_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,
    'claimKind',c.claim_kind,
    'claimValue',c.claim_value,
    'confidence',c.confidence,
    'effectiveFrom',c.effective_from,
    'effectiveTo',c.effective_to,
    'basis',c.basis,
    'sourceRecordId',c.source_record_id,
    'createdAt',c.created_at
  ) order by c.created_at,c.id),'[]'::jsonb)
  into v_claims
  from atlas.identity_claims c
  where c.organization_id=v_subject.organization_id
    and c.subject_id=v_subject.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'assertionId',a.id,
    'sourceRecordId',a.source_record_id,
    'sourceSystemKey',r.source_system_key,
    'sourceRecordKind',r.source_record_kind,
    'sourceRecordKey',r.source_record_key,
    'sourceAuthority',r.source_authority,
    'sourceObservedAt',r.source_observed_at,
    'assertionKind',a.assertion_kind,
    'confidence',a.confidence,
    'basis',a.basis,
    'createdAt',a.created_at
  ) order by a.created_at,a.id),'[]'::jsonb)
  into v_source_bindings
  from atlas.identity_source_subject_assertions a
  join atlas.identity_source_records r on r.id=a.source_record_id
  where a.organization_id=v_subject.organization_id
    and a.subject_id=v_subject.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'assertionId',p.id,
    'leftSubjectId',p.left_subject_id,
    'rightSubjectId',p.right_subject_id,
    'assertionKind',p.assertion_kind,
    'confidence',p.confidence,
    'sourceRecordId',p.source_record_id,
    'basis',p.basis,
    'createdAt',p.created_at
  ) order by p.created_at,p.id),'[]'::jsonb)
  into v_pair_assertions
  from atlas.identity_subject_pair_assertions p
  where p.organization_id=v_subject.organization_id
    and (p.left_subject_id=v_subject.id or p.right_subject_id=v_subject.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'adjudicationId',a.id,
    'reviewId',a.review_id,
    'decisionKind',a.decision_kind,
    'sourceRecordId',a.source_record_id,
    'subjectId',a.subject_id,
    'relatedSubjectId',a.related_subject_id,
    'claimId',a.claim_id,
    'supersedesAdjudicationId',a.supersedes_adjudication_id,
    'basis',a.basis,
    'adjudicatedByLabel',a.adjudicated_by_label,
    'createdAt',a.created_at
  ) order by a.created_at,a.id),'[]'::jsonb)
  into v_adjudications
  from atlas.identity_reconciliation_adjudications a
  where a.organization_id=v_subject.organization_id
    and (a.subject_id=v_subject.id or a.related_subject_id=v_subject.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'reviewId',r.id,
    'reviewKind',r.review_kind,
    'sourceRecordId',r.source_record_id,
    'leftSubjectId',r.left_subject_id,
    'rightSubjectId',r.right_subject_id,
    'claimId',r.claim_id,
    'status',r.status,
    'priority',r.priority,
    'candidateData',r.candidate_data,
    'resolutionSummary',r.resolution_summary,
    'createdAt',r.created_at,
    'resolvedAt',r.resolved_at
  ) order by r.created_at,r.id),'[]'::jsonb)
  into v_reviews
  from atlas.identity_reconciliation_reviews r
  where r.organization_id=v_subject.organization_id
    and (
      r.left_subject_id=v_subject.id
      or r.right_subject_id=v_subject.id
      or r.claim_id in (select c.id from atlas.identity_claims c where c.subject_id=v_subject.id)
    );

  return jsonb_build_object(
    'contractVersion','identity_subject_provenance_v1',
    'subjectId',v_subject.id,
    'organizationId',v_subject.organization_id,
    'reviewerMembershipId',v_membership_id,
    'party',atlas.identity_party_projection_v1(v_subject.id),
    'claims',v_claims,
    'sourceBindings',v_source_bindings,
    'subjectPairAssertions',v_pair_assertions,
    'adjudications',v_adjudications,
    'reviews',v_reviews
  );
end;
$function$;

create or replace function atlas.identity_review_queue_v1(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_membership_id uuid;
  v_items jsonb;
begin
  v_membership_id := atlas.require_identity_steward_v1(p_organization_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'reviewId',r.id,
    'reviewKind',r.review_kind,
    'sourceRecordId',r.source_record_id,
    'leftSubjectId',r.left_subject_id,
    'rightSubjectId',r.right_subject_id,
    'claimId',r.claim_id,
    'priority',r.priority,
    'candidateData',r.candidate_data,
    'openedBy',r.opened_by,
    'createdAt',r.created_at,
    'reviewChoices',case
      when r.review_kind in ('source_binding','subject_equivalence') then jsonb_build_array('same','different','not_enough_evidence')
      when r.review_kind='split_correction' then jsonb_build_array('split','keep_together','not_enough_evidence')
      else jsonb_build_array('accept','reject','not_enough_evidence')
    end
  ) order by
    case r.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
    r.created_at,
    r.id
  ),'[]'::jsonb)
  into v_items
  from atlas.identity_reconciliation_reviews r
  where r.organization_id=p_organization_id
    and r.status='open';

  return jsonb_build_object(
    'contractVersion','identity_review_queue_v1',
    'organizationId',p_organization_id,
    'reviewerMembershipId',v_membership_id,
    'state',case when jsonb_array_length(v_items)=0 then 'clear' else 'review_required' end,
    'pendingCount',jsonb_array_length(v_items),
    'items',v_items
  );
end;
$function$;

create or replace function atlas.identity_adjudicate_review_v1(
  p_review_id uuid,
  p_decision text,
  p_basis text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_review atlas.identity_reconciliation_reviews%rowtype;
  v_membership_id uuid;
  v_decision text := lower(btrim(coalesce(p_decision,'')));
  v_basis text := nullif(btrim(coalesce(p_basis,'')),'');
  v_user_id uuid := auth.uid();
  v_reviewer_label text;
  v_decision_kind text;
  v_assertion_id uuid;
  v_adjudication_id uuid;
  v_evidence jsonb;
  v_resolves_review boolean := true;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if v_decision not in ('same','different','not_enough_evidence','split','keep_together','accept','reject') then
    raise exception 'Unsupported identity review decision.' using errcode='22023';
  end if;
  if v_basis is null then
    raise exception 'A reviewer basis is required.' using errcode='22023';
  end if;
  if length(v_basis)>4000 then
    raise exception 'Reviewer basis is too long.' using errcode='22023';
  end if;

  select * into v_review
  from atlas.identity_reconciliation_reviews
  where id=p_review_id
  for update;

  if v_review.id is null then
    raise exception 'Identity review item not found.' using errcode='P0002';
  end if;

  v_membership_id := atlas.require_identity_steward_v1(v_review.organization_id);

  if v_review.status<>'open' then
    raise exception 'Identity review item is no longer pending.' using errcode='22023';
  end if;

  if v_review.review_kind in ('source_binding','subject_equivalence')
     and v_decision not in ('same','different','not_enough_evidence') then
    raise exception 'Choose Same, Different, or Not enough evidence for this identity review.' using errcode='22023';
  elsif v_review.review_kind='split_correction'
     and v_decision not in ('split','keep_together','not_enough_evidence') then
    raise exception 'Choose Split, Keep together, or Not enough evidence for this correction review.' using errcode='22023';
  elsif v_review.review_kind not in ('source_binding','subject_equivalence','split_correction')
     and v_decision not in ('accept','reject','not_enough_evidence') then
    raise exception 'Choose Accept, Reject, or Not enough evidence for this review.' using errcode='22023';
  end if;

  select coalesce(nullif(btrim(up.display_name),''),v_user_id::text)
  into v_reviewer_label
  from atlas.user_profiles up
  where up.user_id=v_user_id;
  v_reviewer_label := coalesce(v_reviewer_label,v_user_id::text);

  v_evidence := jsonb_build_object(
    'reviewKind',v_review.review_kind,
    'sourceRecordId',v_review.source_record_id,
    'leftSubjectId',v_review.left_subject_id,
    'rightSubjectId',v_review.right_subject_id,
    'claimId',v_review.claim_id,
    'candidateData',v_review.candidate_data
  );

  if v_decision='not_enough_evidence' then
    v_decision_kind := 'defer_unresolved';
    v_resolves_review := false;

  elsif v_review.review_kind='source_binding' then
    if v_review.source_record_id is null or v_review.left_subject_id is null then
      raise exception 'Source-binding review is missing source/subject evidence.' using errcode='23514';
    end if;

    insert into atlas.identity_source_subject_assertions(
      organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
    ) values (
      v_review.organization_id,
      v_review.source_record_id,
      v_review.left_subject_id,
      case when v_decision='same' then 'supports' else 'non_match' end,
      1,
      v_basis,
      'identity-review:'||v_review.id::text||':'||v_decision,
      v_user_id
    ) returning id into v_assertion_id;

    v_decision_kind := case when v_decision='same' then 'accept_source_binding' else 'reject_source_binding' end;

  elsif v_review.review_kind='subject_equivalence' then
    if v_review.left_subject_id is null or v_review.right_subject_id is null then
      raise exception 'Subject-equivalence review is missing subject evidence.' using errcode='23514';
    end if;

    insert into atlas.identity_subject_pair_assertions(
      organization_id,left_subject_id,right_subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
    ) values (
      v_review.organization_id,
      v_review.left_subject_id,
      v_review.right_subject_id,
      case when v_decision='same' then 'equivalent' else 'distinct' end,
      1,
      v_basis,
      'identity-review:'||v_review.id::text||':'||v_decision,
      v_user_id
    ) returning id into v_assertion_id;

    v_decision_kind := case when v_decision='same' then 'subjects_equivalent' else 'subjects_distinct' end;

  elsif v_review.review_kind in ('classification','claim_conflict') then
    if v_review.claim_id is null then
      raise exception 'Claim review is missing claim evidence.' using errcode='23514';
    end if;
    v_decision_kind := case when v_decision='accept' then 'accept_claim' else 'reject_claim' end;

  elsif v_review.review_kind='split_correction' then
    if v_review.left_subject_id is null or v_review.right_subject_id is null then
      raise exception 'Split-correction review is missing subject evidence.' using errcode='23514';
    end if;

    if v_decision='split' then
      insert into atlas.identity_subject_pair_assertions(
        organization_id,left_subject_id,right_subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id
      ) values (
        v_review.organization_id,
        v_review.left_subject_id,
        v_review.right_subject_id,
        'distinct',
        1,
        v_basis,
        'identity-review:'||v_review.id::text||':'||v_decision,
        v_user_id
      ) returning id into v_assertion_id;
      v_decision_kind := 'split_correction';
    else
      v_decision_kind := 'reject_split_correction';
    end if;

  else
    v_decision_kind := case when v_decision='accept' then 'accept_claim' else 'reject_claim' end;
  end if;

  insert into atlas.identity_reconciliation_adjudications(
    organization_id,
    review_id,
    decision_kind,
    source_record_id,
    subject_id,
    related_subject_id,
    claim_id,
    evidence_snapshot,
    basis,
    adjudicated_by_user_id,
    adjudicated_by_label
  ) values (
    v_review.organization_id,
    v_review.id,
    v_decision_kind,
    v_review.source_record_id,
    v_review.left_subject_id,
    v_review.right_subject_id,
    v_review.claim_id,
    v_evidence || jsonb_build_object('decision',v_decision,'resolvedReview',v_resolves_review),
    v_basis,
    v_user_id,
    v_reviewer_label
  ) returning id into v_adjudication_id;

  if v_resolves_review then
    update atlas.identity_reconciliation_reviews
    set status='resolved',
        resolution_summary=v_decision||': '||v_basis
    where id=v_review.id;
  else
    update atlas.identity_reconciliation_reviews
    set resolution_summary='Still unresolved: '||v_basis
    where id=v_review.id;
  end if;

  return jsonb_build_object(
    'contractVersion','identity_adjudicate_review_v1',
    'reviewId',v_review.id,
    'organizationId',v_review.organization_id,
    'reviewerMembershipId',v_membership_id,
    'decision',v_decision,
    'decisionKind',v_decision_kind,
    'reviewState',case when v_resolves_review then 'resolved' else 'open' end,
    'assertionId',v_assertion_id,
    'adjudicationId',v_adjudication_id,
    'canonicalPartyRowCreated',false
  );
end;
$function$;

revoke all on function atlas.require_identity_steward_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_party_projection_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_subject_provenance_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_review_queue_v1(uuid) from public,anon,authenticated;
revoke all on function atlas.identity_adjudicate_review_v1(uuid,text,text) from public,anon,authenticated;

grant execute on function atlas.identity_party_projection_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_subject_provenance_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_review_queue_v1(uuid) to authenticated,service_role;
grant execute on function atlas.identity_adjudicate_review_v1(uuid,text,text) to authenticated,service_role;
grant execute on function atlas.require_identity_steward_v1(uuid) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,anonymous_execute_expected,service_execute_expected,
  security_definer_expected,caller_count,policy_reference_count,evidence
) values
(
  'atlas.identity_party_projection_v1(uuid)','app_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_party_projection_v1',
    'purpose','Read the ordinary Party projection over a reconciled identity subject.',
    'authorizationBoundary','Requires authenticated organization membership; exposes projection only, not identity custody internals.',
    'partyIsProjection',true
  )
),
(
  'atlas.identity_subject_provenance_v1(uuid)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_subject_provenance_v1',
    'purpose','Inspect identity evidence, assertions, reviews and adjudications for one subject.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority.',
    'rawMutationExposed',false
  )
),
(
  'atlas.identity_review_queue_v1(uuid)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_review_queue_v1',
    'purpose','Read unresolved Core identity reconciliation work for one Atlas organization.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority.',
    'threeWayReview',true,
    'dependsOnLocalIntel',false
  )
),
(
  'atlas.identity_adjudicate_review_v1(uuid, text, text)','owner_admin_endpoint','provisional','active',
  true,false,true,true,0,0,
  jsonb_build_object(
    'contractVersion','identity_adjudicate_review_v1',
    'purpose','Record one governed identity decision and its append-only assertion/adjudication consequence.',
    'authorizationBoundary','Requires Owner or Consultant identity-steward authority and re-reads a pending Core review item.',
    'notEnoughEvidenceRemainsOpen',true,
    'canonicalPartyRowCreated',false,
    'dependsOnLocalIntel',false
  )
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  service_execute_expected=excluded.service_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=now();
