begin;

create or replace function atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(
  p_destination_proposal_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_destination atlas.personal_reality_effect_proposals%rowtype;
  v_anchor atlas.personal_reality_effect_proposals%rowtype;
  v_capture atlas.personal_reality_captures%rowtype;
  v_case_id uuid;
  v_thread jsonb;
  v_thread_id uuid;
  v_participant_id uuid;
  v_entry_id uuid;
  v_existing atlas.implementation_conversation_entries%rowtype;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_destination
  from atlas.personal_reality_effect_proposals p
  where p.id=p_destination_proposal_id
    and p.owner_user_id=v_uid
    and p.effect_kind='institutional_destination'
    and p.decision_state='confirmed'
    and p.route_state='applied'
    and p.destination_kind='implementation_case'
  for update;

  if v_destination.id is null then
    raise exception 'Applied Implementation Case destination required.'
      using errcode='42501';
  end if;

  v_case_id:=nullif(v_destination.destination_id,'')::uuid;

  select * into v_capture
  from atlas.personal_reality_captures c
  where c.id=v_destination.capture_id
    and c.owner_user_id=v_uid;

  if v_capture.id is null then
    raise exception 'Personal Reality capture not found.'
      using errcode='P0002';
  end if;

  select * into v_anchor
  from atlas.personal_reality_effect_proposals p
  where p.id=(v_destination.proposal->>'sourceInstitutionalAnchorProposalId')::uuid
    and p.owner_user_id=v_uid
    and p.principal_id=v_destination.principal_id
    and p.capture_id=v_destination.capture_id
    and p.effect_kind='institutional_anchor'
    and p.decision_state='confirmed';

  if v_anchor.id is null then
    raise exception 'Confirmed source Institutional Anchor required.'
      using errcode='42501';
  end if;

  if not atlas.implementation_case_conversation_authorized_self_v1(v_case_id) then
    raise exception 'Implementation conversation authority required.'
      using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      'personal-institutional-implementation-handoff:'||v_destination.id::text,
      0
    )
  );

  select * into v_existing
  from atlas.implementation_conversation_entries e
  where e.implementation_case_id=v_case_id
    and e.entry_kind='text'
    and e.metadata->>'personalInstitutionalDestinationProposalId'=v_destination.id::text
  order by e.created_at,e.id
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,
      'created',false,
      'contractVersion','personal_institutional_implementation_handoff_v1',
      'implementationCaseId',v_case_id,
      'implementationThreadId',v_existing.implementation_thread_id,
      'conversationEntryId',v_existing.id,
      'implementationRealityCandidateCreated',false
    );
  end if;

  v_thread:=atlas.ensure_implementation_conversation_thread_self_api_v1(
    v_case_id,
    'Atlas intake'
  );
  v_thread_id:=nullif(v_thread->>'implementationThreadId','')::uuid;

  if v_thread_id is null then
    raise exception 'Shared Implementation intake thread unavailable.'
      using errcode='55000';
  end if;

  select cp.id into v_participant_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=v_case_id
    and cp.human_user_id=v_uid
    and cp.active
    and cp.ended_at is null
  order by cp.started_at desc,cp.id
  limit 1;

  if v_participant_id is null then
    raise exception 'Active Implementation participant identity required for testimony handoff.'
      using errcode='42501';
  end if;

  insert into atlas.implementation_conversation_entries(
    implementation_case_id,
    implementation_thread_id,
    author_user_id,
    author_participant_id,
    entry_kind,
    body,
    metadata
  ) values (
    v_case_id,
    v_thread_id,
    v_uid,
    v_participant_id,
    'text',
    v_capture.testimony,
    jsonb_build_object(
      'source','personal_institutional_implementation_handoff_v1',
      'personalRealityCaptureId',v_capture.id,
      'sourceEvidenceId',v_capture.evidence_id,
      'institutionalAnchorProposalId',v_anchor.id,
      'personalInstitutionalDestinationProposalId',v_destination.id,
      'literalTestimonyPreserved',true,
      'implementationRealityCandidateCreated',false
    )
  )
  returning id into v_entry_id;

  return jsonb_build_object(
    'ok',true,
    'created',true,
    'contractVersion','personal_institutional_implementation_handoff_v1',
    'implementationCaseId',v_case_id,
    'implementationThreadId',v_thread_id,
    'conversationEntryId',v_entry_id,
    'sourceEvidenceId',v_capture.evidence_id,
    'implementationRealityCandidateCreated',false,
    'truthBoundary',jsonb_build_object(
      'conversationEntryIsIncomingTestimonyNotPractitionerAdjudication',true,
      'literalTestimonyPreserved',true,
      'doesNotCreateCanonicalReality',true,
      'doesNotCreateCommercialReality',true
    )
  );
end;
$function$;

revoke all on function atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(uuid)
  from public,anon,authenticated,service_role;
grant execute on function atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(uuid)
  to authenticated;

create or replace function public.handoff_personal_institutional_destination_to_implementation_self_api_v1(
  p_destination_proposal_id uuid
)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(
    p_destination_proposal_id
  );
$function$;

revoke all on function public.handoff_personal_institutional_destination_to_implementation_self_api_v1(uuid)
  from public,anon,service_role;
grant execute on function public.handoff_personal_institutional_destination_to_implementation_self_api_v1(uuid)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values (
  'atlas.handoff_personal_institutional_destination_to_implementation_self_api_v1(uuid)',
  'app_endpoint','verified','active',
  true,true,false,1,1,
  jsonb_build_object(
    'source','personal_institutional_implementation_handoff_v1',
    'purpose','Post exact Personal Reality testimony into a selected existing Implementation Case participant conversation with source provenance.',
    'truthBoundary','Incoming participant testimony only. Does not create a practitioner Reality Candidate, canonical institutional truth, or commercial truth.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;
