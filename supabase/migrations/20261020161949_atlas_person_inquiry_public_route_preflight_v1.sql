begin;

-- Option C: read-only routing preflight over one exact private inquiry.
-- This does not determine a person's identity, authorize sending, or create
-- any relationship, login, invitation, permission, or correspondence.

create function atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(
  p_ledger_id uuid,
  p_inquiry_id uuid
) returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_owned jsonb;
  v_address text;
  v_public_candidate_count integer;
  v_public_route_state text;
begin
  -- The existing owner reader enforces signed-in canonical Person, active
  -- native Ledger seat, root-governing Principal and exact owner+Ledger scope.
  v_owned:=atlas.person_contact_inquiry_intent_owner_self_api_v1(
    p_ledger_id,p_inquiry_id);
  v_address:=lower(btrim(v_owned->>'observedEmail'));
  if v_address is null then
    raise exception 'Inquiry has no source email observation'
      using errcode='23514';
  end if;

  -- Only independently disclosed, current, general-outreach-authorized
  -- email claims can qualify as a PUBLIC candidate route.
  -- Historical Reality contact_routes or Legacy contact_points alone are
  -- NOT permissions; private source-person identity signals are not read.
  select count(distinct e.id)::integer into v_public_candidate_count
  from local_intel.entity_evidence_claims claim
  join local_intel.entities e on e.id=claim.entity_id
    and e.entity_type='person' and e.status='active'
  join reality.entities canonical on canonical.id=e.id
    and canonical.entity_kind='person'
    and canonical.identity_state='canonical'
  where claim.claim_kind='email'
    and lower(btrim(coalesce(claim.normalized_value,claim.value_text,'')))=v_address
    and claim.lifecycle_state='current'
    and claim.disclosure_posture='public_contactable'
    and 'directory_display'=any(claim.permitted_uses)
    and 'outreach'=any(claim.permitted_uses)
    and 'general'=any(claim.contact_intents)
    and (claim.contact_channel='email' or claim.contact_channel is null)
    and (claim.valid_from is null or claim.valid_from<=current_date)
    and (claim.valid_until is null or claim.valid_until>=current_date)
    and exists (
      select 1 from local_intel.v_contactability_v1 cp
      where cp.entity_id=e.id
        and cp.contact_type='email'
        and cp.effective_contactability='direct_contactable'
        and lower(btrim(cp.contact_value))=v_address
    )
    and not exists (
      select 1 from local_intel.entity_contact_suppressions s
      where s.entity_id=e.id
        and (s.evidence_claim_id is null or s.evidence_claim_id=claim.id)
        and s.suppression_state='active'
        and s.suppression_scope in ('outreach','all_use')
        and s.effective_from<=now()
        and (s.effective_until is null or s.effective_until>now())
    );

  v_public_route_state:=case
    when v_public_candidate_count=1 then 'public_person_route_candidate'
    when v_public_candidate_count>1 then 'multiple_public_routes_require_review'
    else 'no_public_person_route_warrant'
  end;

  -- Caller supplied the email in its own Ledger. Lack of an eligible public
  -- claim neither proves that a Person does not exist nor authorizes contacting
  -- the address. All outbound correspondence awaits distinct approval.
  -- Never return candidate IDs, other-Ledger identifiers, private match
  -- scores, relationship assertions or another party's account status.
  return jsonb_build_object(
    'inquiryId',p_inquiry_id,
    'routeReviewState',v_public_route_state,
    'suppliedAddressUse','separate_sender_authorization_required',
    'identityResolution','not_verified',
    'recipientIdentityDisclosed',false,
    'crossLedgerPrivateLookupPerformed',false,
    'outboundCorrespondenceApproved',false,
    'canSend',false,
    'messageSent',false,
    'stageOneResponse','not_requested',
    'stageTwoRelationship','not_requested',
    'relationshipEstablished',false,
    'next','review_correspondence_sender_and_contact_authority'
  );
end $fn$;

revoke all on function atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(
  uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(
  uuid,uuid) to authenticated;

create function public.person_contact_inquiry_route_preflight_owner_self_api_v1(
  p_ledger_id uuid,p_inquiry_id uuid
) returns jsonb language sql stable security invoker set search_path to ''
as $fn$
  select atlas.person_contact_inquiry_route_preflight_owner_self_api_v1(
    p_ledger_id,p_inquiry_id);
$fn$;

revoke all on function public.person_contact_inquiry_route_preflight_owner_self_api_v1(
  uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.person_contact_inquiry_route_preflight_owner_self_api_v1(
  uuid,uuid) to authenticated;

commit;
