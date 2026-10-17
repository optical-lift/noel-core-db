-- Atlas Build 2/5: governed institutional People, source-defined hats.
-- Read-only projection. No new human identity, appointment, task or delegated grant.
BEGIN;

create or replace function atlas.company_people_native_ledger_scope_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_limit integer default 50,
  p_after_person_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $people$
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
        select 1 from atlas.organization_employee_seats es
        where es.organization_id=p_organization_id
          and es.institutional_person_record_id=people.institutional_person_id
          and es.status='active' and es.ended_at is null
      ) then 'active_organization_seat' else 'not_active' end,
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
$people$;

revoke all on function atlas.company_people_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  from public,anon,authenticated;
grant execute on function atlas.company_people_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)
  to authenticated;

COMMIT;
