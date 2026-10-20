begin;

-- Option C: exact-Ledger, owner-only, NO-SEND sender endpoint preflight.
-- This checks structural prerequisites for a later governed Correspondence
-- decision. Even a positive result is not approval to email the recipient.
-- It neither asserts identity/relationship nor creates any invitation/Work.

create function atlas.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  p_ledger_id uuid,
  p_inquiry_id uuid,
  p_communication_endpoint_id uuid
) returns jsonb
language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_owned jsonb;
  v_ledger atlas.ledgers%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_principal uuid;
  v_reviewed boolean := false;
  v_withdrawn boolean := false;
  v_sender_identity_bound boolean := false;
  v_outbound_source_connected boolean := false;
  v_sender_operation_allowed boolean := false;
  v_sender_operation jsonb;
  v_review_state text := 'owner_source_review_required';
  v_endpoint_state text := 'sender_endpoint_unavailable';
  v_sender_identity_state text := 'not_checked';
  v_outbound_state text := 'not_checked';
  v_responsibility_state text := 'not_checked';
  v_next text := 'complete_owner_source_review';
begin
  -- Existing live helper enforces authenticated canonical Person, current
  -- governing Principal, active native Ledger seat, exact Ledger and exact
  -- inquiry requester ownership; it raises before any private route lookup.
  v_owned := atlas.person_contact_inquiry_intent_owner_self_api_v1(
    p_ledger_id, p_inquiry_id
  );
  v_principal := atlas.current_principal_id_v1();

  select * into v_ledger
  from atlas.ledgers l
  where l.id=p_ledger_id and l.status='active';
  if v_ledger.id is null or v_principal is null then
    raise exception 'Ledger sender review unavailable' using errcode='42501';
  end if;

  select exists (
    select 1 from atlas.person_contact_inquiry_owner_address_reviews r
    where r.inquiry_id=p_inquiry_id and r.ledger_id=p_ledger_id
      and r.decision='owner_source_reviewed'
      and r.reviewed_by_person_id=atlas.current_person_id_v1()
  ) into v_reviewed;

  select exists (
    select 1 from atlas.person_contact_inquiry_owner_address_reviews r
    where r.inquiry_id=p_inquiry_id and r.ledger_id=p_ledger_id
      and r.decision='owner_withdrew_inquiry'
  ) into v_withdrawn;

  if v_withdrawn then
    v_review_state := 'withdrawn';
    v_next := 'no_further_contact_for_this_inquiry';
  elsif v_reviewed then
    v_review_state := 'source_review_recorded';
    v_next := 'choose_authorized_correspondence_endpoint';
  end if;

  -- A withdrawn or unreviewed source does not authorize endpoint probing.
  if v_reviewed and not v_withdrawn and
    p_communication_endpoint_id is not null then
    select * into v_endpoint
    from atlas.communication_endpoints ep
    where ep.id=p_communication_endpoint_id
      and ep.endpoint_kind='email'
      and ep.endpoint_state='active'
      and (
        (v_ledger.organization_id is not null
          and ep.organization_id=v_ledger.organization_id)
        or
        (v_ledger.organization_id is null
          and ep.principal_id=v_principal)
      );

    if v_endpoint.id is not null then
      v_endpoint_state := 'active_scoped_email_endpoint';

      -- Reuse Correspondence's existing presentation identity. A logo,
      -- identity label or endpoint binding alone conveys no sender authority.
      select exists (
        select 1
        from atlas.correspondence_identity_endpoint_bindings b
        join atlas.correspondence_identities ci
          on ci.id=b.correspondence_identity_id
        where b.communication_endpoint_id=v_endpoint.id
          and b.binding_state='active'
          and b.retired_at is null
          and ci.identity_state='active'
          and (
            (v_endpoint.organization_id is not null
              and ci.organization_id=v_endpoint.organization_id
              and (ci.organization_unit_id is null
                   or ci.organization_unit_id=v_endpoint.organization_unit_id))
            or
            (v_endpoint.principal_id is not null
              and ci.principal_id=v_endpoint.principal_id)
          )
      ) into v_sender_identity_bound;

      -- A receive-only or pending source is NOT an outbound route.
      -- This is structural evidence only: provider send capability,
      -- suppression and actual delivery require further checks.
      select exists (
        select 1
        from atlas.communication_endpoint_source_bindings b
        join atlas.connected_sources s on s.id=b.connected_source_id
        where b.communication_endpoint_id=v_endpoint.id
          and b.binding_state='active'
          and b.ended_at is null
          and b.binding_role in ('send','send_receive')
          and s.authorization_state='connected'
          and s.revoked_at is null
          and (
            (v_endpoint.organization_id is not null
              and s.custodian_organization_id=v_endpoint.organization_id)
            or
            (v_endpoint.principal_id is not null
              and s.custodian_user_id=auth.uid())
          )
      ) into v_outbound_source_connected;

      -- Institutional correspondence already resolves actual Person/Reality
      -- responsibility plus the transitional endpoint carrier. It is not
      -- inferred from being an employee, nor from owning this inquiry.
      -- Personal endpoints stay unverified until their own governed send
      -- authority has been checked; this preflight never confers it.
      if v_endpoint.organization_id is not null then
        v_sender_operation :=
          atlas.resolve_institutional_communication_operation_self_v1(
            v_endpoint.id, 'message.send'
          );
        v_sender_operation_allowed :=
          coalesce(v_sender_operation->>'allowed','false')='true';
      end if;

      v_sender_identity_state := case
        when v_sender_identity_bound then 'bound'
        else 'correspondence_identity_binding_required' end;
      v_outbound_state := case
        when v_outbound_source_connected then 'connected_outbound_source_observed'
        else 'connected_outbound_source_required' end;
      v_responsibility_state := case
        when v_sender_operation_allowed then 'existing_operation_authority_observed'
        else 'separate_sender_authority_review_required' end;

      v_next := case
        when not v_sender_identity_bound then 'bind_correspondence_identity'
        when not v_outbound_source_connected then 'connect_authorized_outbound_source'
        when not v_sender_operation_allowed then 'review_actual_person_sender_authority'
        else 'review_recipient_suppression_consent_and_governed_message'
      end;
    end if;
  end if;

  return jsonb_build_object(
    'inquiryId',p_inquiry_id,
    'sourceReviewState',v_review_state,
    'senderEndpointState',v_endpoint_state,
    'correspondenceIdentityState',v_sender_identity_state,
    'outboundSourceState',v_outbound_state,
    'senderResponsibilityState',v_responsibility_state,
    'recipientSuppressionState','not_reviewed',
    'recipientConsentState','not_established',
    'senderTransportVerified',false,
    'outboundCorrespondenceApproved',false,
    'canSend',false,
    'messageSent',false,
    'stageOneResponse','not_requested',
    'stageTwoRelationship','not_requested',
    'personIdentified',false,
    'relationshipEstablished',false,
    'ledgerSeatGranted',false,
    'workAuthorityGranted',false,
    'next',v_next
  );
end $fn$;

revoke all on function atlas.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function atlas.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  uuid,uuid,uuid) to authenticated;

create function public.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  p_ledger_id uuid,
  p_inquiry_id uuid,
  p_communication_endpoint_id uuid
) returns jsonb
language sql stable security invoker set search_path to ''
as $fn$
  select atlas.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
    p_ledger_id,p_inquiry_id,p_communication_endpoint_id
  );
$fn$;
revoke all on function public.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.person_inquiry_sender_endpoint_preflight_owner_self_api_v1(
  uuid,uuid,uuid) to authenticated;

commit;
