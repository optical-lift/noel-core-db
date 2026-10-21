-- Atlas Build 5 physical employee-seat retirement.
-- Source-only until production clone validation and separate protected release.
-- Canonical People, credentials, organization memberships, historical Work and appointments persist.
-- Legacy authenticated institution/worker access now checks exact Person + credential + appointment;
-- the seat subscription is neither identity nor authority.
BEGIN;

DO $preflight$
BEGIN
 IF EXISTS (
   SELECT 1 FROM atlas.organization_employee_seats s
   LEFT JOIN atlas.organization_member_credentials c ON c.employee_seat_id=s.id
   WHERE c.id IS NULL
 ) THEN RAISE EXCEPTION 'Cannot retire an employee seat without a credential provenance receiver'; END IF;
 IF EXISTS (SELECT 1 FROM atlas.company_work_standing_assignment_scopes WHERE employee_seat_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Historical standing scope references must be explicitly migrated first'; END IF;
 IF EXISTS (SELECT 1 FROM atlas.organization_member_exposure_grants WHERE employee_seat_id IS NOT NULL) THEN
   RAISE EXCEPTION 'Historical exposure references must be explicitly migrated first'; END IF;
 IF EXISTS (SELECT 1 FROM atlas.worker_delivery_pilot_sessions WHERE revoked_at IS NULL AND expires_at>now()) THEN
   RAISE EXCEPTION 'Live pilot sessions require independent credential revocation review'; END IF;
 IF EXISTS (SELECT 1 FROM atlas.organization_access_invitations WHERE status='issued') THEN
   RAISE EXCEPTION 'Issued legacy invitations require explicit migration before seat retirement'; END IF;
 IF EXISTS (
   SELECT 1 FROM atlas.organization_member_credentials c
   JOIN atlas.organization_employee_seats s ON s.id=c.employee_seat_id
   JOIN atlas.organization_memberships m ON m.id=c.organization_membership_id
   LEFT JOIN reality.auth_person_bindings b ON b.auth_user_id=c.auth_user_id
     AND b.binding_state='active' AND b.retired_at IS NULL
   LEFT JOIN atlas.principals p ON p.person_id=b.person_entity_id AND p.status='active'
   WHERE c.status='active' AND (m.organization_id<>c.organization_id OR
      m.identity_subject_id IS DISTINCT FROM c.identity_subject_id OR
      m.user_id IS DISTINCT FROM c.auth_user_id OR b.id IS NULL OR p.id IS NULL)
 ) THEN RAISE EXCEPTION 'Credential identity not fully canonical before retirement'; END IF;
END
$preflight$;

-- Preserve the exact retired physical seat and billed state as authenticated
-- credential provenance, NOT as a second active seat or background task.
UPDATE atlas.organization_member_credentials c
SET provenance=jsonb_set(c.provenance,'{retiredEmployeeSeatEvidenceV1}',
  jsonb_build_object('retiredAt',clock_timestamp(),'originalSeatRecord',to_jsonb(s),
    'disposition','legacy_subscription_seat_retired_credential_preserved'),true),
  updated_at=now()
FROM atlas.organization_employee_seats s
WHERE c.employee_seat_id=s.id
  AND NOT (c.provenance ? 'retiredEmployeeSeatEvidenceV1');

-- Retire seat-derived authority from accept_organization_employee_invitation_self_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.accept_organization_employee_invitation_self_api_v1(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
 v_uid uuid:=auth.uid(); v_email text; v_invite atlas.organization_access_invitations%rowtype; v_issuer_ok boolean:=false;
 v_subject_id uuid; v_membership_id uuid; v_seat_id uuid; v_credential_id uuid; v_existing_credential atlas.organization_member_credentials%rowtype;
 v_candidate_count integer:=0; v_candidate_subject uuid; v_review_id uuid; v_source_record_id uuid; v_email_claim_id uuid;
begin
 if v_uid is null then raise exception 'Authentication required.' using errcode='42501'; end if;
 select lower(u.email) into v_email from auth.users u where u.id=v_uid and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
 if v_email is null then raise exception 'Authenticated email unavailable.' using errcode='42501'; end if;
 select * into v_invite from atlas.organization_access_invitations where id=p_invitation_id for update;
 if v_invite.id is null then raise exception 'Organization invitation not found.' using errcode='P0002'; end if;
 if v_invite.invitee_email<>v_email then raise exception 'This invitation is not available to the signed-in account.' using errcode='42501'; end if;
 if v_invite.status='accepted' and v_invite.accepted_by_user_id=v_uid then
   select * into v_existing_credential from atlas.organization_member_credentials c where c.organization_id=v_invite.organization_id and c.auth_user_id=v_uid and c.credential_kind='auth_user' and c.status='active' order by c.created_at limit 1;
   if v_existing_credential.id is not null then return jsonb_build_object('ok',true,'replayed',true,'invitationId',v_invite.id,'identitySubjectId',v_existing_credential.identity_subject_id,'organizationMembershipId',v_existing_credential.organization_membership_id,'employeeSeatId',NULL::uuid,'credentialId',v_existing_credential.id); end if;
 end if;
 if v_invite.status<>'issued' then raise exception 'Invitation is not open for acceptance.' using errcode='55000'; end if;
 if v_invite.expires_at is not null and v_invite.expires_at<=now() then update atlas.organization_access_invitations set status='expired',updated_at=now() where id=v_invite.id; return jsonb_build_object('ok',false,'reason','invitation_expired','invitationId',v_invite.id); end if;
 if v_invite.issuer_kind='organization_owner' then
   v_issuer_ok:=exists(select 1 from atlas.organization_memberships m where m.id=v_invite.issued_by_membership_id and m.organization_id=v_invite.organization_id and m.user_id=v_invite.issued_by_user_id and m.active and m.role='owner');
 else
   v_issuer_ok:=exists(select 1 from atlas.organization_onboarding_actors a where a.organization_id=v_invite.organization_id and a.human_user_id=v_invite.issued_by_user_id and a.active and a.ended_at is null);
 end if;
 if not v_issuer_ok then raise exception 'Invitation issuer authority is no longer valid.' using errcode='42501'; end if;
 select * into v_existing_credential from atlas.organization_member_credentials c where c.organization_id=v_invite.organization_id and c.auth_user_id=v_uid and c.credential_kind='auth_user' and c.status='active' order by c.created_at limit 1;
 if v_existing_credential.id is not null then
   v_subject_id:=v_existing_credential.identity_subject_id; v_membership_id:=v_existing_credential.organization_membership_id; v_seat_id:=NULL::uuid; v_credential_id:=v_existing_credential.id;
 else
   select m.id,m.identity_subject_id into v_membership_id,v_subject_id from atlas.organization_memberships m where m.organization_id=v_invite.organization_id and m.user_id=v_uid and m.active order by m.created_at limit 1;
   if v_subject_id is null and v_invite.intended_identity_subject_id is not null then
     if not exists(select 1 from atlas.identity_subjects s where s.id=v_invite.intended_identity_subject_id and s.organization_id=v_invite.organization_id and s.state='active') then raise exception 'Prebound institutional identity is outside invitation custody.' using errcode='23514'; end if;
     v_subject_id:=v_invite.intended_identity_subject_id;
   end if;
   if v_subject_id is null then
     select count(distinct c.subject_id) into v_candidate_count from atlas.identity_claims c where c.organization_id=v_invite.organization_id and c.claim_kind in ('email','email_address') and lower(btrim(case when jsonb_typeof(c.claim_value)='string' then c.claim_value#>>'{}' else coalesce(c.claim_value->>'value',c.claim_value->>'email',c.claim_value->>'address','') end))=v_email;
     if v_candidate_count>0 then
       select c.subject_id into v_candidate_subject from atlas.identity_claims c where c.organization_id=v_invite.organization_id and c.claim_kind in ('email','email_address') and lower(btrim(case when jsonb_typeof(c.claim_value)='string' then c.claim_value#>>'{}' else coalesce(c.claim_value->>'value',c.claim_value->>'email',c.claim_value->>'address','') end))=v_email order by c.created_at limit 1;
       insert into atlas.identity_reconciliation_reviews(organization_id,review_kind,left_subject_id,status,priority,candidate_data,opened_by) values(v_invite.organization_id,'source_binding',v_candidate_subject,'open','high',jsonb_build_object('reason','employee_invitation_email_matches_existing_identity_evidence','invitationId',v_invite.id,'email',v_email,'candidateCount',v_candidate_count),'organization_access_invitation_v1') returning id into v_review_id;
       return jsonb_build_object('ok',false,'reason','identity_reconciliation_required','invitationId',v_invite.id,'reviewId',v_review_id,'candidateCount',v_candidate_count);
     end if;
     insert into atlas.identity_subjects(organization_id,state,created_by_user_id,creation_basis) values(v_invite.organization_id,'active',v_uid,jsonb_build_object('source','accepted_organization_access_invitation','invitationId',v_invite.id)) returning id into v_subject_id;
   end if;
   insert into atlas.identity_source_records(organization_id,source_system_key,source_record_kind,source_record_key,source_observed_at,source_authority,custody_ref,metadata)
   values(v_invite.organization_id,'atlas_access','organization_employee_invitation',v_invite.id::text,now(),'authoritative_source',jsonb_build_object('invitationId',v_invite.id),jsonb_build_object('authenticatedUserId',v_uid,'inviteeEmail',v_email,'displayName',v_invite.display_name))
   on conflict(organization_id,source_system_key,source_record_kind,source_record_key) do nothing;
   select r.id into v_source_record_id from atlas.identity_source_records r where r.organization_id=v_invite.organization_id and r.source_system_key='atlas_access' and r.source_record_kind='organization_employee_invitation' and r.source_record_key=v_invite.id::text;
   if not exists(select 1 from atlas.identity_claims c where c.source_record_id=v_source_record_id and c.subject_id=v_subject_id and c.claim_kind='email') then
     insert into atlas.identity_claims(organization_id,subject_id,source_record_id,claim_kind,claim_value,confidence,basis,metadata) values(v_invite.organization_id,v_subject_id,v_source_record_id,'email',to_jsonb(v_email),1.0,'Authenticated account accepted an invitation addressed to this email.',jsonb_build_object('credentialVerified',true)) returning id into v_email_claim_id;
     insert into atlas.identity_reconciliation_adjudications(organization_id,decision_kind,source_record_id,subject_id,claim_id,evidence_snapshot,basis,adjudicated_by_user_id,adjudicated_by_label) values(v_invite.organization_id,'accept_claim',v_source_record_id,v_subject_id,v_email_claim_id,jsonb_build_object('invitationId',v_invite.id,'authenticatedUserId',v_uid,'email',v_email),'The authenticated credential carrier accepted the invitation addressed to the same email.',v_uid,'organization_access_invitation_v1');
   end if;
   if not exists(select 1 from atlas.identity_claims c where c.source_record_id=v_source_record_id and c.subject_id=v_subject_id and c.claim_kind='display_name') then
     insert into atlas.identity_claims(organization_id,subject_id,source_record_id,claim_kind,claim_value,confidence,basis) values(v_invite.organization_id,v_subject_id,v_source_record_id,'display_name',to_jsonb(v_invite.display_name),0.9,'Display name supplied by the authorized organization inviter.');
   end if;
   if not exists(select 1 from atlas.identity_source_subject_assertions a where a.source_record_id=v_source_record_id and a.subject_id=v_subject_id and a.assertion_kind='supports') then
     insert into atlas.identity_source_subject_assertions(organization_id,source_record_id,subject_id,assertion_kind,confidence,basis,idempotency_key,created_by_user_id) values(v_invite.organization_id,v_source_record_id,v_subject_id,'supports',1.0,'Authenticated invitation acceptance binds this access record to the institutional subject.','access_invite:'||v_invite.id::text,v_uid);
   end if;
   insert into atlas.identity_subject_projections(subject_id,organization_id,subject_kind,display_name,contact_points,unresolved_identity,confidence,projection_basis)
   values(v_subject_id,v_invite.organization_id,'person',v_invite.display_name,jsonb_build_array(jsonb_build_object('kind','email','value',v_email)),false,1.0,jsonb_build_object('source','accepted_organization_access_invitation','invitationId',v_invite.id))
   on conflict(subject_id) do update set subject_kind=case when atlas.identity_subject_projections.subject_kind='unknown' then 'person' else atlas.identity_subject_projections.subject_kind end,display_name=coalesce(atlas.identity_subject_projections.display_name,excluded.display_name),contact_points=case when atlas.identity_subject_projections.contact_points='[]'::jsonb then excluded.contact_points else atlas.identity_subject_projections.contact_points end,unresolved_identity=false,projection_basis=atlas.identity_subject_projections.projection_basis||excluded.projection_basis,updated_at=now();
   if v_membership_id is null then
     insert into atlas.organization_memberships(organization_id,user_id,role,active,permissions,identity_subject_id,updated_at) values(v_invite.organization_id,v_uid,'member',true,'{}'::jsonb,v_subject_id,now())
     on conflict(organization_id,user_id) do update set active=true,identity_subject_id=coalesce(atlas.organization_memberships.identity_subject_id,excluded.identity_subject_id),updated_at=now() returning id into v_membership_id;
   else update atlas.organization_memberships set identity_subject_id=coalesce(identity_subject_id,v_subject_id),updated_at=now() where id=v_membership_id; end if;
   -- Credential is issued without creating a billed employee seat.
   v_seat_id:=NULL;
   insert into atlas.organization_member_credentials(organization_id,organization_membership_id,identity_subject_id,credential_kind,auth_user_id,status,issued_by_organization_id,provenance)
   values(v_invite.organization_id,v_membership_id,v_subject_id,'auth_user',v_uid,'active',v_invite.organization_id,jsonb_build_object('sourceInvitationId',v_invite.id,'verifiedEmail',v_email)) returning id into v_credential_id;
 end if;
 update atlas.organization_access_invitations set status='accepted',accepted_by_user_id=v_uid,accepted_at=now(),updated_at=now() where id=v_invite.id;
 return jsonb_build_object('ok',true,'replayed',false,'contractVersion','organization_access_invitation_v1','invitationId',v_invite.id,'organizationId',v_invite.organization_id,'identitySubjectId',v_subject_id,'organizationMembershipId',v_membership_id,'employeeSeatId',v_seat_id,'credentialId',v_credential_id,'authorityCreated',false,'positionCreated',false,'responsibilityCreated',false,'exposureGrantCreated',false);
end;$function$;

-- Retire seat-derived authority from admit_existing_verified_person_self_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.admit_existing_verified_person_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_legacy atlas.person_auth_credentials%ROWTYPE;
  v_person atlas.people%ROWTYPE;
  v_entity reality.entities%ROWTYPE;
  v_binding reality.auth_person_bindings%ROWTYPE;
  v_count integer;
  v_eligible boolean;
  v_principal atlas.principals%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sign in required' USING ERRCODE='42501';
  END IF;
  -- Do not trust a passed email or client-controlled user metadata.
  PERFORM 1 FROM auth.users u
    WHERE u.id=v_uid AND u.deleted_at IS NULL AND u.email_confirmed_at IS NOT NULL
      AND NOT coalesce(u.is_anonymous,false)
      AND (u.banned_until IS NULL OR u.banned_until <= now());
  IF NOT FOUND THEN
    RAISE EXCEPTION 'A verified human Auth session is required'
      USING ERRCODE='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.existing_verified_person_admission:'||v_uid::text,0));

  -- One active legacy credential must identify precisely one existing Person.
  SELECT count(*)::integer INTO v_count
    FROM atlas.person_auth_credentials c
    WHERE c.auth_user_id=v_uid
      AND c.credential_kind='supabase_auth_user'
      AND c.status='active' AND c.retired_at IS NULL;
  IF v_count=0 THEN
    RETURN jsonb_build_object('ok',true,'state','not_applicable');
  END IF;
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Multiple active Person credentials require identity review'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO STRICT v_legacy FROM atlas.person_auth_credentials c
    WHERE c.auth_user_id=v_uid
      AND c.credential_kind='supabase_auth_user'
      AND c.status='active' AND c.retired_at IS NULL;
  SELECT * INTO v_person FROM atlas.people p
    WHERE p.id=v_legacy.person_id AND p.status='active';
  IF v_person.id IS NULL OR nullif(btrim(v_person.display_name),'') IS NULL THEN
    RAISE EXCEPTION 'Existing active Person identity required'
      USING ERRCODE='23514';
  END IF;

  -- A recognized Personal Atlas Principal takes the existing, stricter
  -- Principal-specific admission function, not the employee-only path.
  SELECT * INTO v_principal FROM atlas.principals p
    WHERE p.user_id=v_uid AND p.status='active';
  IF v_principal.id IS NOT NULL THEN
    IF v_principal.person_id IS DISTINCT FROM v_person.id THEN
      RAISE EXCEPTION 'Principal/Person identity conflict'
        USING ERRCODE='23514';
    END IF;
    PERFORM atlas.admit_existing_person_identity_self_v1();
    RETURN jsonb_build_object('ok',true,'state','admitted',
      'identityPath','existing_principal');
  END IF;

  -- An employee without a Principal is admitted ONLY if an existing
  -- active institutional credential, membership, seat and Person agree.
  SELECT EXISTS (
    SELECT 1
    FROM atlas.organization_member_credentials oc
    JOIN atlas.organization_memberships m
      ON m.id=oc.organization_membership_id AND m.organization_id=oc.organization_id
    JOIN atlas.organizations o ON o.id=m.organization_id
    WHERE oc.auth_user_id=v_uid AND oc.credential_kind='auth_user'
      AND oc.status='active' AND (oc.expires_at IS NULL OR oc.expires_at>now())
      AND m.person_id=v_legacy.person_id
      AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
      AND oc.identity_subject_id=m.identity_subject_id AND oc.auth_user_id=m.user_id
      AND o.status='active'
  ) INTO v_eligible;
  IF NOT v_eligible THEN
    RETURN jsonb_build_object('ok',true,'state','not_applicable');
  END IF;

  -- No email/name heuristics, different UUIDs, or second Person objects.
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.auth_user_id=v_uid AND b.binding_state='active'
      AND b.retired_at IS NULL
      AND (b.person_entity_id<>v_legacy.person_id OR b.id<>v_legacy.id)
  ) THEN
    RAISE EXCEPTION 'Existing canonical Auth/Person binding conflicts'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.id=v_legacy.id
      AND (b.auth_user_id<>v_uid OR b.person_entity_id<>v_legacy.person_id)
  ) THEN
    RAISE EXCEPTION 'Legacy credential binding ID collision'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.auth_person_bindings b
    WHERE b.person_entity_id=v_legacy.person_id
      AND b.auth_user_id<>v_uid AND b.binding_state='active'
      AND b.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Person is bound to a different active Auth user'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM reality.entities e
    WHERE e.stable_key='legacy-atlas-person:'||v_legacy.person_id::text
      AND e.id<>v_legacy.person_id
  ) THEN
    RAISE EXCEPTION 'Canonical Person stable-key collision'
      USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_entity FROM reality.entities e WHERE e.id=v_legacy.person_id;
  IF v_entity.id IS NOT NULL
    AND (v_entity.entity_kind<>'person' OR v_entity.identity_state<>'canonical') THEN
    RAISE EXCEPTION 'Existing identity is not a canonical Person'
      USING ERRCODE='23514';
  END IF;

  IF v_entity.id IS NULL THEN
    INSERT INTO reality.entities(
      id,stable_key,entity_kind,display_name,identity_state,metadata
    ) VALUES(
      v_legacy.person_id,
      'legacy-atlas-person:'||v_legacy.person_id::text,
      'person',v_person.display_name,'canonical',
      jsonb_build_object('admissionState','existing_verified_employee',
        'source','atlas.person_auth_credentials',
        'admissionContract','shared_existing_verified_person_self_v1')
    );
  END IF;

  SELECT * INTO v_binding FROM reality.auth_person_bindings b
    WHERE b.auth_user_id=v_uid AND b.binding_state='active' AND b.retired_at IS NULL;
  IF v_binding.id IS NULL THEN
    INSERT INTO reality.auth_person_bindings(
      id,auth_user_id,person_entity_id,binding_state,binding_basis,bound_at
    ) VALUES (
      v_legacy.id,v_uid,v_legacy.person_id,'active',
      jsonb_build_object('admissionState','existing_verified_employee',
        'source','atlas.person_auth_credentials',
        'legacyCredentialId',v_legacy.id,
        'legacyProvenance',v_legacy.provenance,
        'contract','shared_existing_verified_person_self_v1'),
      v_legacy.bound_at
    );
  END IF;

  -- The existing auth-binding trigger may create a native Personal Atlas
  -- identity container; this function creates NO Principal, purchase, grant,
  -- authority, institutional seat or new Auth user.
  RETURN jsonb_build_object('ok',true,'state','admitted',
    'identityPath','existing_employee');
END;
$function$;

-- Retire seat-derived authority from atlas_operations_summary_self_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.atlas_operations_summary_self_api_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
  select case
    when not atlas.implementation_practitioner_authorized_self_v1() then
      jsonb_build_object(
        'ok', false,
        'code', 'practitioner_authority_required'
      )
    else
      jsonb_build_object(
        'ok', true,
        'contractVersion', 'atlas_operations_summary_self_api_v1',
        'atlasAccounts', (
          select count(*)
          from auth.users u
          where u.deleted_at is null
            and u.email_confirmed_at is not null
        ),
        'ledgers', (
          select count(*)
          from atlas.ledger_entitlement_bindings b
          where b.ended_at is null
            and b.state in ('bound','activated')
        ),
        'employeeSeats', (
          select 0::bigint
        ),
        'openImplementations', (
          select count(*)
          from atlas.implementation_cases c
          where c.state not in ('closed','cancelled')
        ),
        'ledgerAccountConnections', null,
        'ledgerAccountConnectionsState', 'not_yet_canonical'
      )
  end;
$function$;

-- Retire seat-derived authority from company_people_native_ledger_scope_self_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.company_people_native_ledger_scope_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_limit integer DEFAULT 50, p_after_person_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_viewer_person uuid;
  v_limit integer := coalesce(p_limit,50);
  v_count integer := 0;
  v_items jsonb := '[]'::jsonb;
  v_after uuid;
begin
  if p_organization_id is null or p_ledger_id is null then
    raise exception 'Exact Organization and native Ledger are required.'
      using errcode='22023';
  end if;
  if v_limit < 1 or v_limit > 100 then
    raise exception 'People page size must be between 1 and 100.'
      using errcode='22023';
  end if;

  -- The exact same active Atlas session, canonical Person, native seat,
  -- root governing authority and Organization/Ledger participation gate
  -- used by Build 1. A member seat or position title is not enough.
  v_viewer_person :=
    atlas.company_work_native_ledger_owner_self_v1(
      p_organization_id,p_ledger_id
    );

  select count(*)::integer into v_count
  from (
    select pe.id
    from atlas.institutional_person_records ipr
    join atlas.people pe
      on pe.id=ipr.person_id and pe.status='active'
    where ipr.organization_id=p_organization_id
      and ipr.status='active'
      and (p_after_person_id is null or pe.id>p_after_person_id)
    order by pe.id,ipr.id
    limit v_limit+1
  ) page_size;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'personId',people.person_id,
      'personStableKey',people.person_stable_key,
      'displayName',people.display_name,
      'institutionalPersonRecordId',people.institutional_person_id,
      'organizationId',p_organization_id,
      'institutionalRelationshipState','active_record',
      'organizationMembershipState',case when exists(
        select 1 from atlas.organization_memberships m
        where m.organization_id=p_organization_id
          and m.institutional_person_record_id=people.institutional_person_id
          and m.active
          and (m.eligibility_begins_on is null or m.eligibility_begins_on<=current_date)
          and (m.eligibility_ends_on is null or m.eligibility_ends_on>=current_date)
      ) then 'active_membership' else 'not_established_from_membership' end,
      'positionAppointments',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'appointmentId',a.id,
            'appointmentKind',a.appointment_kind,
            'positionId',pos.id,
            'positionKey',pos.stable_key,
            'positionTitle',pos.display_title,
            'positionKind',pos.position_kind,
            'organizationUnitId',u.id,
            'organizationUnitKey',u.stable_key,
            'organizationUnitName',u.name,
            'ledgerPositionProof','not_established_by_organization_appointment',
            'source','atlas.organization_position_appointments'
          ) order by a.begins_at,a.id
        )
        from atlas.organization_position_appointments a
        join atlas.organization_positions pos
          on pos.id=a.position_id
          and pos.organization_id=p_organization_id
          and pos.status='active'
        join atlas.organization_units u
          on u.id=pos.organization_unit_id
          and u.organization_id=p_organization_id
          and u.status='active'
        where a.institutional_person_record_id=people.institutional_person_id
          and a.organization_id=p_organization_id
          and a.status='active'
          and a.begins_at<=now()
          and (a.ends_at is null or a.ends_at>now())
      ),'[]'::jsonb),
      'durableResponsibilityScopes',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'appointmentId',r.appointment_id,
            'positionId',r.position_id,
            'responsibilityId',r.responsibility_id,
            'responsibilityName',r.responsibility_name,
            'scopeKind',r.scope_kind,
            'scopeId',r.scope_id,
            'resolutionState',r.resolution_state,
            'evidenceSource','atlas.effective_person_organization_responsibilities_current_v2'
          ) order by r.position_id,r.responsibility_id,r.scope_kind,r.scope_id
        )
        from atlas.effective_person_organization_responsibilities_current_v2(
          people.person_id,p_organization_id
        ) r
      ),'[]'::jsonb),
      'nativeLedgerSeatState',case when exists(
        select 1 from ledger.seats s
        where s.ledger_id=p_ledger_id
          and s.person_entity_id=people.person_id
          and s.seat_state='active' and s.ended_at is null
      ) then 'active_participation_only' else 'not_proven' end,
      'employeeDeliverySeatState',case when exists(
        select 1 from atlas.organization_member_credentials c
         join atlas.organization_memberships m on m.id=c.organization_membership_id
         where c.organization_id=p_organization_id
           and m.institutional_person_record_id=people.institutional_person_id
           and c.identity_subject_id=m.identity_subject_id
           and c.credential_kind='auth_user' and c.auth_user_id=m.user_id
           and c.status='active' and (c.expires_at is null or c.expires_at>now())
      ) then 'active_organization_credential' else 'not_active' end,
      'institutionalCredentialState',case when exists(
        select 1 from atlas.organization_member_credentials c
        join atlas.organization_memberships m
          on m.id=c.organization_membership_id
          and m.organization_id=p_organization_id
          and m.institutional_person_record_id=people.institutional_person_id
        where c.organization_id=p_organization_id
          and c.status='active'
          and c.auth_user_id is not null
          and c.revoked_at is null
          and (c.expires_at is null or c.expires_at>now())
      ) then 'active_institutional_auth_credential'
        else 'no_current_institutional_auth_credential_proven' end,
      'exactLedgerPositionState','unresolved_without_source_appointment',
      'companyWorkState','not_projected_in_build_2',
      'privatePersonalAtlasState','not_read',
      'source', 'atlas.institutional_person_records'
    ) order by people.person_id
  ),'[]'::jsonb)
  into v_items
  from (
    select
      pe.id as person_id,
      pe.stable_key as person_stable_key,
      pe.display_name,
      ipr.id as institutional_person_id
    from atlas.institutional_person_records ipr
    join atlas.people pe
      on pe.id=ipr.person_id and pe.status='active'
    where ipr.organization_id=p_organization_id
      and ipr.status='active'
      and (p_after_person_id is null or pe.id>p_after_person_id)
    order by pe.id,ipr.id
    limit v_limit
  ) people;

  if jsonb_array_length(v_items)>0 then
    v_after:=(v_items->(jsonb_array_length(v_items)-1)->>'personId')::uuid;
  end if;

  return jsonb_build_object(
    'contractVersion','company_people_native_ledger_scope_v1',
    'organizationId',p_organization_id,
    'ledgerId',p_ledger_id,
    'viewerPersonId',v_viewer_person,
    'items',v_items,
    'hasMore',v_count>v_limit,
    'nextPersonId',case when v_count>v_limit then v_after else null end,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'currentOnly',true,
      'institutionalPeopleNotAnAddressBook',true,
      'personIsNotCredential',true,
      'organizationMembershipIsNotNativeLedgerAppointment',true,
      'nativeLedgerSeatIsParticipationNotEmploymentOrAuthority',true,
      'organizationPositionDoesNotProveLedgerHat',true,
      'roleDoesNotAssignCompanyWork',true,
      'durableResponsibilityDoesNotGrantExecution',true,
      'privatePersonalAtlasNotRead',true,
      'delegationAndWorkerDayRequireSeparateAuthorizedContracts',true,
      'rootOwnerScopeOnlyV1',true
    )
  );
end;
$function$;

-- Retire seat-derived authority from company_work_execution_membership_check_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.company_work_execution_membership_check_v1(p_work_item_id uuid, p_assignee_membership_id uuid, p_service_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_org_member atlas.organization_memberships%rowtype;
  v_credential atlas.organization_member_credentials%rowtype;
  v_farm_id uuid;
  v_count integer:=0;
  v_farm_membership_id uuid;
begin
  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return jsonb_build_object('allowed',false,'state','missing_work'); end if;

  if not atlas.organization_membership_eligible_on_date_v1(p_assignee_membership_id,v_work.organization_id,p_service_date) then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_eligible');
  end if;

  select * into v_org_member
  from atlas.organization_memberships
  where id=p_assignee_membership_id and organization_id=v_work.organization_id;

  if v_org_member.id is null then
    return jsonb_build_object('allowed',false,'state','organization_membership_not_found');
  end if;

  if v_org_member.role='member' then
    SELECT * INTO v_credential FROM atlas.organization_member_credentials c
    WHERE c.organization_id=v_work.organization_id
      AND c.organization_membership_id=v_org_member.id
      AND c.identity_subject_id=v_org_member.identity_subject_id
      AND c.auth_user_id=v_org_member.user_id
      AND c.credential_kind='auth_user' AND c.status='active'
      AND (c.expires_at IS NULL OR c.expires_at>now())
    ORDER BY c.issued_at LIMIT 1;
    IF v_credential.id IS NULL THEN RETURN jsonb_build_object(
      'allowed',false,'state','active_verified_organization_credential_required',
      'organizationMembershipId',v_org_member.id); END IF;
  end if;

  select pwo.farm_id into v_farm_id
  from atlas.work_execution_adapters a
  join atlas.planned_work_occurrences pwo on pwo.id=a.planned_occurrence_id
  where a.organization_id=v_work.organization_id and a.work_item_id=v_work.id and a.state='active'
  order by a.created_at limit 1;

  if v_farm_id is null then
    return jsonb_strip_nulls(jsonb_build_object(
      'allowed',true,
      'state','no_farm_execution_carrier',
      'organizationMembershipId',p_assignee_membership_id,
      'employeeSeatId',NULL::uuid
    ));
  end if;

  select count(*),min(fm.id::text)::uuid into v_count,v_farm_membership_id
  from atlas.farm_memberships fm
  where fm.farm_id=v_farm_id
    and fm.user_id=v_org_member.user_id
    and fm.role='farm_hand'
    and atlas.farm_membership_eligible_on_date_v1(fm.id,v_farm_id,p_service_date);

  return jsonb_strip_nulls(jsonb_build_object(
    'allowed',v_count=1,
    'state',case
      when v_count=1 then 'eligible_worker'
      when v_count=0 then 'no_eligible_worker_membership'
      else 'ambiguous_worker_membership'
    end,
    'farmId',v_farm_id,
    'organizationMembershipId',p_assignee_membership_id,
    'employeeSeatId',NULL::uuid,
    'farmMembershipId',case when v_count=1 then v_farm_membership_id else null end,
    'matchingWorkerMemberships',v_count,
    'workerRole','farm_hand'
  ));
end;
$function$;

-- Retire seat-derived authority from organization_access_physical_compatibility_internal_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_access_physical_compatibility_internal_v1()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','atlas','auth'
AS $function$
DECLARE v_uid uuid:=auth.uid();v_person_id uuid;v_items jsonb;
BEGIN
 IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',true,'authenticated',false,'items','[]'::jsonb);END IF;
 v_person_id:=atlas.current_person_id_v1();
 IF v_person_id IS NULL THEN RETURN jsonb_build_object('ok',true,'authenticated',true,
   'contractVersion','organization_access_self_v1','items','[]'::jsonb);END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'organizationId',o.id,'organizationName',o.name,'organizationMembershipId',m.id,
   'identitySubjectId',m.identity_subject_id,'employeeSeatId',NULL::uuid,
   'accessClass','employee','seatStatus','retired','billingState','retired',
   'membershipRole',m.role,'accessBasis','verified_organization_member_credential')
   ORDER BY o.name,o.id),'[]'::jsonb) INTO v_items
 FROM atlas.organization_member_credentials c
 JOIN atlas.organization_memberships m ON m.id=c.organization_membership_id
   AND m.organization_id=c.organization_id AND m.identity_subject_id=c.identity_subject_id
   AND m.user_id=c.auth_user_id
 JOIN atlas.organizations o ON o.id=m.organization_id
 WHERE c.credential_kind='auth_user' AND c.auth_user_id=v_uid
   AND c.status='active' AND (c.expires_at IS NULL OR c.expires_at>now())
   AND m.person_id=v_person_id
   AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
   AND o.status='active';
 RETURN jsonb_build_object('ok',true,'authenticated',true,'contractVersion','organization_access_self_v1','items',v_items);
END
$function$;

-- Retire seat-derived authority from organization_company_work_people_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_company_work_people_api_v1(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_delivery_candidates jsonb := '[]'::jsonb;
  v_members jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_organization_id is null then
    raise exception 'Organization required.' using errcode='22023';
  end if;
  if not atlas.is_organization_owner(p_organization_id)
     and not exists(
       select 1
       from atlas.farms f
       join atlas.farm_memberships fm on fm.farm_id=f.id
       where f.organization_id=p_organization_id
         and fm.user_id=v_uid
         and fm.active
         and fm.role in ('owner','manager')
     ) then
    raise exception 'Organization management authority required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(item order by item->>'organizationUnitName',item->>'displayName',item->>'deliveryMembershipId'),'[]'::jsonb)
  into v_delivery_candidates
  from (
    select jsonb_strip_nulls(jsonb_build_object(
      'deliveryMembershipId',fm.id,
      'farmId',f.id,
      'farmName',f.name,
      'organizationUnitId',f.organization_unit_id,
      'organizationUnitName',ou.name,
      'authUserId',fm.user_id,
      'email',u.email,
      'displayName',coalesce(isp.display_name,nullif(fm.worker_key,''),split_part(coalesce(u.email,''),'@',1)),
      'deliveryRole',fm.role,
      'deliveryEligibilityBeginsOn',fm.eligibility_begins_on,
      'deliveryEligibilityEndsOn',fm.eligibility_ends_on,
      'identitySubjectId',fm.identity_subject_id,
      'identityInOrganization',case when ids.id is null then false else true end,
      'suggestedInvitationIdentitySubjectId',case when ids.id is null then null else fm.identity_subject_id end,
      'organizationMembershipId',om.id,
      'employeeSeatId',NULL::uuid,
      'employeeSeatStatus','retired'::text,
      'employeeBillingState','retired'::text,
      'appointmentId',appt.id,
      'positionId',pos.id,
      'positionKey',pos.stable_key,
      'positionTitle',pos.display_title,
      'relationshipState',case
        when om.id is null then 'delivery_only'
        when credential.id is null then 'organization_member_without_employee_access'
        when appt.id is null then 'employee_access_without_position'
        else 'positioned_employee'
      end
    )) item
    from atlas.farms f
    join atlas.farm_memberships fm
      on fm.farm_id=f.id
     and fm.active
    left join atlas.organization_units ou
      on ou.id=f.organization_unit_id
     and ou.organization_id=f.organization_id
    left join auth.users u on u.id=fm.user_id
    left join atlas.identity_subject_projections isp on isp.subject_id=fm.identity_subject_id
    left join atlas.identity_subjects ids
      on ids.id=fm.identity_subject_id
     and ids.organization_id=p_organization_id
     and ids.state='active'
    left join atlas.organization_memberships om
      on om.organization_id=p_organization_id
     and om.user_id=fm.user_id
     and om.active
    left join atlas.organization_member_credentials credential on credential.organization_id=p_organization_id
      and credential.organization_membership_id=om.id AND credential.identity_subject_id=om.identity_subject_id
      AND credential.auth_user_id=om.user_id AND credential.credential_kind='auth_user'
      AND credential.status='active' AND (credential.expires_at IS NULL OR credential.expires_at>now())
    left join lateral(
      select a.*
      from atlas.organization_position_appointments a
      where a.organization_id=p_organization_id
        and a.organization_membership_id=om.id
        and a.status='active'
        and a.begins_at<=now()
        and (a.ends_at is null or a.ends_at>now())
      order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id
      limit 1
    ) appt on true
    left join atlas.organization_positions pos
      on pos.id=appt.position_id
     and pos.organization_id=p_organization_id
    where f.organization_id=p_organization_id
  ) x;

  select coalesce(jsonb_agg(item order by item->>'displayName',item->>'organizationMembershipId'),'[]'::jsonb)
  into v_members
  from (
    select jsonb_strip_nulls(jsonb_build_object(
      'organizationMembershipId',om.id,
      'personId',om.person_id,
      'identitySubjectId',om.identity_subject_id,
      'authUserId',om.user_id,
      'membershipRole',om.role,
      'email',u.email,
      'displayName',coalesce(pe.display_name,isp.display_name,split_part(coalesce(u.email,''),'@',1)),
      'employeeSeatId',NULL::uuid,
      'employeeSeatStatus','retired'::text,
      'employeeBillingState','retired'::text,
      'appointmentId',appt.id,
      'positionId',pos.id,
      'positionKey',pos.stable_key,
      'positionTitle',pos.display_title,
      'organizationUnitId',pos.organization_unit_id,
      'organizationUnitName',ou.name
    )) item
    from atlas.organization_memberships om
    left join atlas.people pe on pe.id=om.person_id
    left join atlas.identity_subject_projections isp on isp.subject_id=om.identity_subject_id
    left join auth.users u on u.id=om.user_id
    left join atlas.organization_member_credentials credential on credential.organization_id=om.organization_id
      and credential.organization_membership_id=om.id AND credential.identity_subject_id=om.identity_subject_id
      AND credential.auth_user_id=om.user_id AND credential.credential_kind='auth_user'
      AND credential.status='active' AND (credential.expires_at IS NULL OR credential.expires_at>now())
    left join lateral(
      select a.*
      from atlas.organization_position_appointments a
      where a.organization_id=om.organization_id
        and a.organization_membership_id=om.id
        and a.status='active'
        and a.begins_at<=now()
        and (a.ends_at is null or a.ends_at>now())
      order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id
      limit 1
    ) appt on true
    left join atlas.organization_positions pos on pos.id=appt.position_id
    left join atlas.organization_units ou on ou.id=pos.organization_unit_id
    where om.organization_id=p_organization_id
      and om.active
  ) x;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','organization_company_work_people_v1',
    'organizationId',p_organization_id,
    'deliveryCandidates',v_delivery_candidates,
    'members',v_members
  );
end;
$function$;

-- Retire seat-derived authority from organization_employee_appointments_by_auth_user_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_employee_appointments_by_auth_user_v1(
p_auth_user_id uuid,p_organization_id uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $function$
WITH eligible AS (
 SELECT c.id credential_id,c.organization_id,c.organization_membership_id,c.identity_subject_id
 FROM atlas.organization_member_credentials c
 JOIN atlas.organization_memberships m ON m.id=c.organization_membership_id
  AND m.organization_id=c.organization_id AND m.identity_subject_id=c.identity_subject_id
  AND m.user_id=c.auth_user_id
 JOIN atlas.organizations o ON o.id=c.organization_id AND o.status='active'
 WHERE c.credential_kind='auth_user' AND c.auth_user_id=p_auth_user_id
  AND c.status='active' AND (c.expires_at IS NULL OR c.expires_at>now())
  AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
  AND (p_organization_id IS NULL OR c.organization_id=p_organization_id)
), appts AS (
 SELECT e.*,a.id appointment_id,a.appointment_kind,p.id position_id,p.stable_key position_key,
  p.display_title,p.position_kind,p.organization_unit_id,u.stable_key organization_unit_key,
  u.name organization_unit_name,u.unit_kind organization_unit_kind
 FROM eligible e
 JOIN atlas.organization_position_appointments a ON a.organization_id=e.organization_id
  AND a.organization_membership_id=e.organization_membership_id AND a.identity_subject_id=e.identity_subject_id
  AND a.status='active' AND a.begins_at<=now() AND (a.ends_at IS NULL OR a.ends_at>now())
 JOIN atlas.organization_positions p ON p.id=a.position_id AND p.organization_id=e.organization_id AND p.status='active'
 JOIN atlas.organization_units u ON u.id=p.organization_unit_id AND u.organization_id=e.organization_id AND u.status='active'
)
SELECT jsonb_build_object('ok',true,'contractVersion','organization_employee_appointments_by_auth_user_v1',
 'items',coalesce(jsonb_agg(jsonb_build_object(
  'credentialId',credential_id,'employeeSeatId',NULL::uuid,'organizationId',organization_id,
  'organizationMembershipId',organization_membership_id,'identitySubjectId',identity_subject_id,
  'appointmentId',appointment_id,'appointmentKind',appointment_kind,'positionId',position_id,
  'positionKey',position_key,'displayTitle',display_title,'positionKind',position_kind,
  'organizationUnitId',organization_unit_id,'organizationUnitKey',organization_unit_key,
  'organizationUnitName',organization_unit_name,'organizationUnitKind',organization_unit_kind
 ) ORDER BY appointment_kind,position_key),'[]'::jsonb)) FROM appts
$function$;

-- Retire seat-derived authority from organization_employee_context_by_auth_user_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_employee_context_by_auth_user_v1(
p_auth_user_id uuid,p_organization_id uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog','atlas'
AS $function$
 SELECT coalesce((SELECT jsonb_build_object('ok',true,'organizationId',m.organization_id,
  'organizationMembershipId',m.id,'identitySubjectId',m.identity_subject_id,
  'employeeSeatId',NULL::uuid,'seatClass','retired','billingState','retired','credentialId',c.id,
  'accessBasis','verified_organization_member_credential')
 FROM atlas.organization_member_credentials c
 JOIN atlas.organization_memberships m ON m.id=c.organization_membership_id
  AND m.organization_id=c.organization_id AND m.identity_subject_id=c.identity_subject_id
  AND m.user_id=c.auth_user_id
 JOIN atlas.organizations o ON o.id=m.organization_id AND o.status='active'
 WHERE c.credential_kind='auth_user' AND c.auth_user_id=p_auth_user_id
  AND c.status='active' AND (c.expires_at IS NULL OR c.expires_at>now())
  AND atlas.organization_membership_present_effective_at_v1(m.id,m.organization_id,now())
  AND (p_organization_id IS NULL OR m.organization_id=p_organization_id)
 LIMIT 1),jsonb_build_object('ok',false,'code','no_active_verified_organization_credential'))
$function$;

-- Retire seat-derived authority from organization_employee_worker_context_self_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_employee_worker_context_self_v1(p_farm_id uuid, p_delivery_membership_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_farm atlas.farms%rowtype;
  v_farm_member atlas.farm_memberships%rowtype;
  v_org_member atlas.organization_memberships%rowtype;

  v_position atlas.organization_positions%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
  v_timezone text:='America/Chicago';
  v_today date;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'reason','authentication_required'); end if;
  if p_farm_id is null or p_delivery_membership_id is null then return jsonb_build_object('ok',false,'reason','worker_context_required'); end if;
  select * into v_farm from atlas.farms f where f.id=p_farm_id;
  if v_farm.id is null or v_farm.organization_id is null or v_farm.organization_unit_id is null then return jsonb_build_object('ok',false,'reason','institutional_farm_context_required'); end if;
  v_timezone:=coalesce(nullif(v_farm.metadata->>'timezone',''),'America/Chicago');
  if not exists(select 1 from pg_timezone_names where name=v_timezone) then v_timezone:='America/Chicago'; end if;
  v_today:=(now() at time zone v_timezone)::date;
  select * into v_farm_member from atlas.farm_memberships fm where fm.id=p_delivery_membership_id and fm.farm_id=p_farm_id and fm.user_id=v_uid and fm.active=true and fm.role='farm_hand' and fm.identity_subject_id is not null;
  if v_farm_member.id is null then return jsonb_build_object('ok',false,'reason','active_worker_membership_required'); end if;
  if not atlas.farm_membership_eligible_on_date_v1(v_farm_member.id,p_farm_id,v_today) then return jsonb_build_object('ok',false,'reason','worker_membership_not_eligible'); end if;
  select * into v_org_member from atlas.organization_memberships m where m.organization_id=v_farm.organization_id and m.user_id=v_uid and m.identity_subject_id=v_farm_member.identity_subject_id and m.active=true and m.role='member' order by m.created_at limit 1;
  if v_org_member.id is null then return jsonb_build_object('ok',false,'reason','employee_organization_membership_required'); end if;
  if not atlas.organization_membership_eligible_on_date_v1(v_org_member.id,v_farm.organization_id,v_today) then return jsonb_build_object('ok',false,'reason','employee_organization_membership_not_eligible'); end if;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_member_credentials c
    WHERE c.organization_id=v_farm.organization_id AND c.organization_membership_id=v_org_member.id
      AND c.identity_subject_id=v_org_member.identity_subject_id
      AND c.auth_user_id=v_uid AND c.credential_kind='auth_user'
      AND c.status='active' AND (c.expires_at IS NULL OR c.expires_at>now())
  ) THEN RETURN jsonb_build_object('ok',false,'reason','active_verified_organization_credential_required'); END IF;
  select a.* into v_appointment from atlas.organization_position_appointments a join atlas.organization_positions p on p.id=a.position_id and p.organization_id=a.organization_id and p.status='active' where a.organization_id=v_farm.organization_id and a.organization_membership_id=v_org_member.id and a.identity_subject_id=v_org_member.identity_subject_id and a.status='active' and a.begins_at<=now() and (a.ends_at is null or a.ends_at>now()) and p.organization_unit_id=v_farm.organization_unit_id order by case when a.appointment_kind='primary' then 0 else 1 end,a.begins_at,a.id limit 1;
  if v_appointment.id is null then return jsonb_build_object('ok',false,'reason','active_worker_appointment_required'); end if;
  select * into v_position from atlas.organization_positions p where p.id=v_appointment.position_id and p.organization_id=v_farm.organization_id and p.organization_unit_id=v_farm.organization_unit_id and p.status='active';
  if v_position.id is null then return jsonb_build_object('ok',false,'reason','active_worker_position_required'); end if;
  return jsonb_build_object('ok',true,'contractVersion','organization_employee_worker_context_v1','organizationId',v_farm.organization_id,'organizationUnitId',v_farm.organization_unit_id,'organizationMembershipId',v_org_member.id,'deliveryMembershipId',v_farm_member.id,'identitySubjectId',v_org_member.identity_subject_id,'employeeSeatId',NULL::uuid,'appointmentId',v_appointment.id,'positionId',v_position.id,'positionKey',v_position.stable_key,'positionTitle',v_position.display_title,'serviceDate',v_today);
end;
$function$;

-- Retire seat-derived authority from organization_owner_appoint_employee_position_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.organization_owner_appoint_employee_position_api_v1(p_organization_id uuid, p_organization_membership_id uuid, p_position_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_member atlas.organization_memberships%rowtype;
  v_position atlas.organization_positions%rowtype;
  v_existing atlas.organization_position_appointments%rowtype;
  v_appointment atlas.organization_position_appointments%rowtype;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_organization_id is null or p_organization_membership_id is null or p_position_id is null then
    raise exception 'Organization, employee membership, and Position are required.' using errcode='22023';
  end if;
  if not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Organization owner authority required.' using errcode='42501';
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.id=p_organization_membership_id
    and m.organization_id=p_organization_id
    and m.active
    and m.identity_subject_id is not null;
  if v_member.id is null then
    raise exception 'Active employee Organization Membership with institutional identity required.' using errcode='23514';
  end if;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.organization_member_credentials c
    JOIN atlas.organizations o ON o.id=c.organization_id AND o.status='active'
    WHERE c.organization_id=p_organization_id
      AND c.organization_membership_id=v_member.id
      AND c.identity_subject_id=v_member.identity_subject_id
      AND c.auth_user_id=v_member.user_id AND c.credential_kind='auth_user'
      AND c.status='active' AND (c.expires_at IS NULL OR c.expires_at>now())
  ) THEN RAISE EXCEPTION 'Active verified Organization credential required before Position appointment.' USING ERRCODE='23514'; END IF;
  select * into v_position
  from atlas.organization_positions p
  where p.id=p_position_id
    and p.organization_id=p_organization_id
    and p.status='active';
  if v_position.id is null then
    raise exception 'Active Position in this Organization required.' using errcode='23514';
  end if;

  select * into v_existing
  from atlas.organization_position_appointments a
  where a.organization_id=p_organization_id
    and a.position_id=p_position_id
    and a.identity_subject_id=v_member.identity_subject_id
    and a.organization_membership_id=v_member.id
    and a.status='active'
    and a.begins_at<=now()
    and (a.ends_at is null or a.ends_at>now())
  order by a.begins_at,a.id
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'state','unchanged',
      'appointmentId',v_existing.id,
      'organizationMembershipId',v_member.id,
      'positionId',v_position.id,
      'positionKey',v_position.stable_key,
      'positionTitle',v_position.display_title
    );
  end if;

  insert into atlas.organization_position_appointments(
    organization_id,position_id,identity_subject_id,organization_membership_id,
    appointment_kind,status,begins_at,metadata
  ) values(
    p_organization_id,v_position.id,v_member.identity_subject_id,v_member.id,
    'primary','active',now(),jsonb_strip_nulls(jsonb_build_object(
      'source','organization_owner_appoint_employee_position_api_v1',
      'appointedByUserId',v_uid,
      'reason',nullif(btrim(coalesce(p_reason,'')),'')
    ))
  ) returning * into v_appointment;

  return jsonb_build_object(
    'state','appointed',
    'appointmentId',v_appointment.id,
    'organizationMembershipId',v_member.id,
    'positionId',v_position.id,
    'positionKey',v_position.stable_key,
    'positionTitle',v_position.display_title
  );
end;
$function$;

-- Retire seat-derived authority from propose_native_ledger_standing_scope_owner_self_api_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.propose_native_ledger_standing_scope_owner_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_worker_person_id uuid, p_organization_unit_id uuid, p_coverage_mode text, p_operation_class text, p_terms text, p_valid_until timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_owner_membership uuid;
 v_scope atlas.company_work_standing_assignment_scopes%ROWTYPE;
 v_terms text:=nullif(btrim(coalesce(p_terms,'')),'');
 v_class text:=nullif(btrim(coalesce(p_operation_class,'')),'');
 v_mode text:=lower(btrim(coalesce(p_coverage_mode,'')));
BEGIN
 IF auth.uid() IS NULL OR p_worker_person_id IS NULL OR
    (v_mode IS NULL OR v_mode NOT IN ('operation_class','ledger_all_work')) OR
    (v_mode='operation_class' AND (p_organization_unit_id IS NULL OR
       v_class IS NULL OR length(v_class) NOT BETWEEN 2 AND 120)) OR
    (v_mode='ledger_all_work' AND (p_organization_unit_id IS NOT NULL OR v_class IS NOT NULL)) OR
    v_terms IS NULL OR
    length(v_terms) NOT BETWEEN 30 AND 3000 OR
    (p_valid_until IS NOT NULL AND p_valid_until<=now()) THEN
   RAISE EXCEPTION 'A canonical Person, operating unit, bounded terms and valid expiry are required'
      USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_owner=p_worker_person_id THEN
   RAISE EXCEPTION 'Owner self-work uses a separate authorized path' USING ERRCODE='23514';
 END IF;
 v_owner_membership:=atlas.current_effective_organization_membership_v1(p_organization_id);
 IF NOT EXISTS(SELECT 1 FROM atlas.organization_memberships m WHERE
     m.id=v_owner_membership AND m.organization_id=p_organization_id
     AND m.person_id=v_owner AND m.role='owner' AND m.active) THEN
   RAISE EXCEPTION 'Authorized owner membership required' USING ERRCODE='42501';
 END IF;
 IF NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,p_worker_person_id) THEN
   RAISE EXCEPTION 'Active exact native Ledger Person connection required' USING ERRCODE='23514';
 END IF;
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.organization_units u
     WHERE u.id=p_organization_unit_id AND u.organization_id=p_organization_id
       AND u.status='active') THEN
   RAISE EXCEPTION 'Active exact organization unit required' USING ERRCODE='23514';
 END IF;
 -- One recorded operation class, not unrelated Work in the same unit.
 IF v_mode='operation_class' AND NOT EXISTS(SELECT 1 FROM atlas.work_items work
   WHERE work.organization_id=p_organization_id
     AND work.organization_unit_id=p_organization_unit_id
     AND work.operation_class=v_class) THEN
   RAISE EXCEPTION 'Standing responsibility class must exist in this operating unit'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.company_work_standing_assignment_scopes s
     WHERE s.organization_id=p_organization_id AND s.ledger_id=p_ledger_id
       AND s.worker_person_id=p_worker_person_id
       AND s.organization_unit_id IS NOT DISTINCT FROM p_organization_unit_id
       AND s.covered_operation_class IS NOT DISTINCT FROM v_class
       AND s.coverage_mode=v_mode
       AND s.scope_state IN ('proposed','active')
       AND (s.valid_until IS NULL OR s.valid_until>now())) THEN
   RAISE EXCEPTION 'A standing scope already exists for this exact Person and unit'
       USING ERRCODE='23505';
 END IF;
 INSERT INTO atlas.company_work_standing_assignment_scopes(
   organization_id,ledger_id,worker_membership_id,worker_person_id,
   position_id,position_appointment_id,organization_unit_id,
   covered_operation_class,coverage_mode,proposed_by_person_id,proposed_by_membership_id,proposal_terms,valid_until
 ) VALUES (
   p_organization_id,p_ledger_id,NULL,p_worker_person_id,
   NULL,NULL,p_organization_unit_id,
   v_class,v_mode,v_owner,v_owner_membership,v_terms,p_valid_until
 ) RETURNING * INTO v_scope;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','native_ledger_standing_scope_v1',
   'scopeId',v_scope.id,'state','proposed','organizationId',p_organization_id,
   'ledgerId',p_ledger_id,'workerPersonId',p_worker_person_id,
   'organizationUnitId',p_organization_unit_id,'operationClass',v_class,
   'coverageMode',v_mode,
   'workerConsentRecorded',false,'workAssigned',false,'employeeSeatRequired',false);
END
$function$;

-- Retire seat-derived authority from semantic_exposure_envelope_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.semantic_exposure_envelope_v1(p_organization_id uuid, p_audience_membership_id uuid, p_purpose_key text, p_candidate jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_membership atlas.organization_memberships%rowtype;
  v_credential atlas.organization_member_credentials%rowtype;
  v_policy atlas.semantic_exposure_policies%rowtype;
  v_claim atlas.claim_records%rowtype;
  v_claim_id uuid;
  v_adapter_key text;
  v_information_class text;
  v_semantic_kind text;
  v_predicate_key text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_value_kind text;
  v_value jsonb;
  v_value_unit text;
  v_now timestamptz := now();
  v_envelope jsonb;
begin
  if p_organization_id is null or p_audience_membership_id is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_audience_context');
  end if;

  select * into v_membership
  from atlas.organization_memberships m
  where m.id=p_audience_membership_id
    and m.organization_id=p_organization_id
    and m.active=true;

  if v_membership.id is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','inactive_or_foreign_membership');
  end if;

  SELECT * INTO v_credential FROM atlas.organization_member_credentials c
  WHERE c.organization_membership_id=v_membership.id AND c.organization_id=p_organization_id
    AND c.identity_subject_id=v_membership.identity_subject_id AND c.auth_user_id=v_membership.user_id
    AND c.credential_kind='auth_user' AND c.status='active'
    AND (c.expires_at IS NULL OR c.expires_at>now())
  ORDER BY c.issued_at LIMIT 1;
  IF v_credential.id IS NULL THEN RETURN jsonb_build_object(
    'contractVersion','semantic_exposure_envelope_v1','admitted',false,
    'reason','active_verified_organization_credential_required'); END IF;

  if p_purpose_key not in ('worker_day','employer_drawer','worker_action') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','unsupported_purpose');
  end if;

  if not atlas.semantic_exposure_candidate_shape_valid_v1(p_candidate) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_candidate_shape');
  end if;

  v_adapter_key:=btrim(p_candidate->>'adapterKey');
  v_information_class:=btrim(p_candidate->>'informationClass');
  v_semantic_kind:=btrim(p_candidate->>'semanticKind');
  v_predicate_key:=btrim(p_candidate->>'predicateKey');
  v_source_domain:=btrim(p_candidate->>'sourceDomain');
  v_source_kind:=btrim(p_candidate->>'sourceKind');
  v_source_id:=btrim(p_candidate->>'sourceId');
  v_value_kind:=btrim(p_candidate->>'valueKind');
  v_value:=p_candidate->'value';
  v_value_unit:=nullif(btrim(coalesce(p_candidate->>'valueUnit','')),'');

  if v_adapter_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_predicate_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_domain !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_kind !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_source_id='' then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_semantic_identity');
  end if;

  if v_information_class in ('organization_internal','person_private','restricted') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','information_class_not_worker_exposable');
  end if;

  if not exists (
    select 1 from atlas.organization_member_exposure_grants g
    where g.organization_id=p_organization_id
      and g.organization_membership_id=p_audience_membership_id
      and g.active=true
      and g.information_class=v_information_class
  ) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','member_exposure_not_granted');
  end if;

  if not atlas.claim_value_matches_kind_v2(v_value_kind,v_value) then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_typed_value');
  end if;

  if v_value_unit is not null and (v_value_kind<>'number' or v_value_unit !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$') then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','invalid_value_unit');
  end if;

  select * into v_policy
  from atlas.semantic_exposure_policies p
  where p.active
    and p.audience_kind='organization_member'
    and p.purpose_key=p_purpose_key
    and p.information_class=v_information_class
    and p.semantic_kind=v_semantic_kind
    and p.predicate_key=v_predicate_key
    and p.adapter_key=v_adapter_key
    and p.source_domain=v_source_domain
    and p.source_kind=v_source_kind
  limit 1;

  if v_policy.policy_key is null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','no_explicit_admission_policy');
  end if;

  if v_semantic_kind='claim' then
    begin v_claim_id:=nullif(btrim(coalesce(p_candidate->>'claimId','')),'')::uuid;
    exception when invalid_text_representation then v_claim_id:=null;
    end;
    if v_claim_id is null then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_identity_required');
    end if;
    select * into v_claim from atlas.claim_records c where c.id=v_claim_id;
    if v_claim.id is null
       or v_claim.semantic_contract_version is distinct from 'claim-v2'
       or v_claim.scope_kind is distinct from 'organization'
       or v_claim.scope_id is distinct from p_organization_id then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_outside_exposure_custody');
    end if;
    if v_claim.predicate_key is distinct from v_predicate_key
       or v_claim.value_kind is distinct from v_value_kind
       or v_claim.value is distinct from v_value
       or v_claim.value_unit is distinct from v_value_unit then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_projection_mismatch');
    end if;
    if not (v_claim.modality=any(v_policy.allowed_modalities)) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_modality_not_admitted');
    end if;
    if not (v_claim.adjudication_state=any(v_policy.allowed_adjudication_states)) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_adjudication_not_admitted');
    end if;
    if (v_claim.valid_from is not null and v_claim.valid_from>v_now)
       or (v_claim.valid_until is not null and v_claim.valid_until<=v_now) then
      return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_not_current_in_time');
    end if;
  elsif nullif(btrim(coalesce(p_candidate->>'claimId','')),'') is not null then
    return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',false,'reason','claim_identity_on_non_claim_candidate');
  end if;

  v_envelope:=jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','semantic_exposure_envelope_v1',
    'organizationId',p_organization_id,
    'audienceMembershipId',p_audience_membership_id,
    'employeeSeatId',NULL::uuid,
    'audienceKind','organization_member',
    'purposeKey',p_purpose_key,
    'informationClass',v_information_class,
    'semanticKind',v_semantic_kind,
    'predicateKey',v_predicate_key,
    'value',jsonb_strip_nulls(jsonb_build_object('kind',v_value_kind,'value',v_value,'unit',v_value_unit)),
    'provenance',jsonb_strip_nulls(jsonb_build_object(
      'policyKey',v_policy.policy_key,
      'adapterKey',v_adapter_key,
      'source',jsonb_build_object('domain',v_source_domain,'kind',v_source_kind,'id',v_source_id),
      'claim',case when v_claim.id is not null then jsonb_build_object('id',v_claim.id,'modality',v_claim.modality,'adjudicationState',v_claim.adjudication_state,'primaryEvidenceId',v_claim.primary_evidence_id) else null end
    ))
  ));

  return jsonb_build_object('contractVersion','semantic_exposure_envelope_v1','admitted',true,'reason','explicit_policy_and_member_grant','envelope',v_envelope);
end;
$function$;

-- Retire seat-derived authority from worker_delivery_pilot_session_status_v1 without changing its call signature.
CREATE OR REPLACE FUNCTION atlas.worker_delivery_pilot_session_status_v1(p_session_token_hash text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
  select coalesce((
    select jsonb_build_object('ok',true,'sessionId',s.id,'membershipId',c.delivery_membership_id,
      'organizationMembershipId',c.organization_membership_id,'employeeSeatId',NULL::uuid,'expiresAt',s.expires_at)
    from atlas.worker_delivery_pilot_sessions s
    join atlas.worker_delivery_pilot_capabilities c on c.id=s.capability_id
    join atlas.organization_memberships om on om.id=c.organization_membership_id and om.active=true and om.role='member'
    join atlas.farm_memberships fm on fm.id=c.delivery_membership_id and fm.active=true and fm.role='farm_hand'
      and fm.user_id=om.user_id and fm.identity_subject_id=om.identity_subject_id
    join atlas.farms f on f.id=fm.farm_id and f.organization_id=om.organization_id and f.organization_unit_id is not null
    join atlas.organization_member_credentials cred on cred.organization_id=om.organization_id
      and cred.organization_membership_id=om.id and cred.identity_subject_id=om.identity_subject_id
      and cred.auth_user_id=om.user_id and cred.credential_kind='auth_user'
      and cred.status='active' and (cred.expires_at is null or cred.expires_at>clock_timestamp())
    join atlas.organization_position_appointments appt on appt.organization_id=om.organization_id
      and appt.organization_membership_id=om.id and appt.identity_subject_id=om.identity_subject_id
      and appt.status='active' and appt.begins_at<=clock_timestamp() and (appt.ends_at is null or appt.ends_at>clock_timestamp())
    join atlas.organization_positions pos on pos.id=appt.position_id and pos.organization_id=om.organization_id
      and pos.organization_unit_id=f.organization_unit_id and pos.status='active'
    where s.session_token_hash=p_session_token_hash and s.revoked_at is null and s.expires_at>clock_timestamp()
      and c.revoked_at is null and c.expires_at>clock_timestamp() and c.scope='anna_worker_day_pilot'
      and atlas.organization_membership_eligible_on_date_v1(om.id,om.organization_id,(clock_timestamp() at time zone 'America/Chicago')::date)
      and atlas.farm_membership_eligible_on_date_v1(fm.id,fm.farm_id,(clock_timestamp() at time zone 'America/Chicago')::date)
    limit 1
  ),jsonb_build_object('ok',false,'code','invalid_or_expired_session'));
$function$;

-- The archive must actually contain each original seat before any FK column
-- can be removed. Empty schema-only clones legitimately contain zero such rows.
DO $archive_check$
BEGIN
 IF EXISTS (
   SELECT 1 FROM atlas.organization_employee_seats s
   WHERE NOT EXISTS (
     SELECT 1 FROM atlas.organization_member_credentials c
     WHERE c.employee_seat_id=s.id
       AND c.provenance->'retiredEmployeeSeatEvidenceV1'->'originalSeatRecord'->>'id'=s.id::text
       AND c.provenance->'retiredEmployeeSeatEvidenceV1'->>'disposition'=
         'legacy_subscription_seat_retired_credential_preserved'
   )
 ) THEN RAISE EXCEPTION 'An original employee seat has not been archived to credential provenance'; END IF;
END
$archive_check$;

-- Drop the three now-unused FK-bearing seat columns. Credential, scope
-- and exposure records remain (their exact audit evidence was preserved).
ALTER TABLE atlas.company_work_standing_assignment_scopes DROP COLUMN employee_seat_id;
ALTER TABLE atlas.organization_member_exposure_grants DROP COLUMN employee_seat_id;
ALTER TABLE atlas.organization_member_credentials DROP COLUMN employee_seat_id;

-- RESTRICT refuses to erase any undiscovered dependent schema object.
DROP TABLE atlas.organization_employee_seats RESTRICT;
DROP FUNCTION atlas.guard_institutional_person_seat_bridge_v1();

DO $post$
BEGIN
 IF to_regclass('atlas.organization_employee_seats') IS NOT NULL THEN
   RAISE EXCEPTION 'Physical employee seat table still exists';END IF;
 IF EXISTS(SELECT 1 FROM atlas.organization_member_credentials
      WHERE status='active' AND credential_kind='auth_user'
        AND provenance ? 'retiredEmployeeSeatEvidenceV1' AND auth_user_id IS NULL) THEN
    RAISE EXCEPTION 'Archived credential lost its authenticated account';END IF;
END
$post$;
COMMIT;
