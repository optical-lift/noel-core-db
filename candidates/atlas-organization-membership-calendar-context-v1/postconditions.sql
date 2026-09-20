-- Behavioral postconditions for Organization Membership Calendar Context v1.
-- Run only in a disposable production-schema clone after fixture.sql + candidate.sql.

do $proof$
declare
  setup_org constant uuid := 'ca110000-0000-4000-8000-000000000001'::uuid;
  setup_user constant uuid := 'ca100000-0000-4000-8000-000000000001'::uuid;
  setup_member constant uuid := 'ca110000-0000-4000-8000-000000000031'::uuid;
  root_org constant uuid := 'ca210000-0000-4000-8000-000000000001'::uuid;
  root_principal constant uuid := 'ca200000-0000-4000-8000-000000000031'::uuid;
  missing_org constant uuid := 'ca310000-0000-4000-8000-000000000001'::uuid;
  v_result jsonb;
  v_first uuid;
  v_second uuid;
  v_root uuid;
  v_failed boolean;
  v_date_utc date;
  v_date_tokyo date;
  v_count integer;
  v_elm uuid;
begin
  -- 1. Exact live compatibility adjudication exists only for Elm Farm.
  select o.id into v_elm from atlas.organizations o where o.stable_key='elm_farm';

  select count(*)::integer into v_count
  from atlas.organization_membership_calendar_contexts c
  where c.organization_id=v_elm
    and c.context_state='active'
    and c.timezone_name='America/Chicago'
    and c.basis_kind='current_state_compatibility_adjudication';

  if v_count<>1 then
    raise exception 'Elm Farm compatibility calendar context count expected 1, got %.',v_count;
  end if;

  if exists(
    select 1
    from atlas.organization_membership_calendar_contexts c
    join atlas.organizations o on o.id=c.organization_id
    where o.stable_key in ('feast_guild','atlas_reference_company')
  ) then
    raise exception 'Current unbounded Organizations received invented Membership Calendar Context.';
  end if;

  -- 2. Browser and service roles do not receive direct table mutation/read authority.
  if has_table_privilege('anon','atlas.organization_membership_calendar_contexts','SELECT')
     or has_table_privilege('authenticated','atlas.organization_membership_calendar_contexts','SELECT')
     or has_table_privilege('authenticated','atlas.organization_membership_calendar_contexts','INSERT')
     or has_table_privilege('service_role','atlas.organization_membership_calendar_contexts','INSERT')
     or has_table_privilege('service_role','atlas.organization_membership_calendar_contexts','UPDATE') then
    raise exception 'Membership Calendar Context table leaked direct role authority.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.set_organization_membership_calendar_context_internal_v1(uuid,text,text,uuid,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated browser can execute internal Membership Calendar Context command.';
  end if;

  -- 3. Invalid timezone names fail closed.
  v_failed:=false;
  begin
    insert into atlas.organization_membership_calendar_contexts(
      organization_id,timezone_name,basis_kind,authority_evidence,metadata
    ) values (
      missing_org,'Mars/Olympus_Mons','current_state_compatibility_adjudication',
      '{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
    );
  exception when sqlstate '22023' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Invalid timezone name was accepted.';
  end if;

  -- 4. Missing context remains unresolved rather than falling back to session/Principal/domain time.
  if atlas.organization_membership_calendar_date_at_v1(
       missing_org,'2026-09-20 02:30:00+00'::timestamptz
     ) is not null then
    raise exception 'Missing Membership Calendar Context silently fell back to ambient time.';
  end if;

  -- 5. Active setup actor can establish exact context with canonical Person provenance.
  v_result:=atlas.set_organization_membership_calendar_context_internal_v1(
    setup_org,'America/Chicago','organization_setup_actor_declaration',
    setup_user,null,'fixture declaration','{"validation_fixture":true}'::jsonb
  );
  v_first:=(v_result->>'contextId')::uuid;

  if v_first is null
     or not exists(
       select 1
       from atlas.organization_membership_calendar_contexts c
       where c.id=v_first
         and c.organization_id=setup_org
         and c.context_state='active'
         and c.timezone_name='America/Chicago'
         and c.established_by_setup_actor_user_id=setup_user
         and c.established_by_person_id='ca100000-0000-4000-8000-000000000011'::uuid
     ) then
    raise exception 'Setup actor declaration did not establish exact provenance: %',v_result;
  end if;

  -- 6. Explicit date-scoped Membership eligibility semantics remain unchanged.
  if atlas.organization_membership_eligible_on_date_v1(
       setup_member,setup_org,'2026-09-09'::date
     )
     or not atlas.organization_membership_eligible_on_date_v1(
       setup_member,setup_org,'2026-09-10'::date
     )
     or not atlas.organization_membership_eligible_on_date_v1(
       setup_member,setup_org,'2026-09-30'::date
     )
     or atlas.organization_membership_eligible_on_date_v1(
       setup_member,setup_org,'2026-10-01'::date
     ) then
    raise exception 'Explicit service-date Membership eligibility behavior changed.';
  end if;

  -- 7. Civil date derives from exact context timezone, independent of session timezone.
  perform set_config('TimeZone','UTC',true);
  v_date_utc:=atlas.organization_membership_calendar_date_at_v1(
    setup_org,'2026-09-20 02:30:00+00'::timestamptz
  );

  perform set_config('TimeZone','Asia/Tokyo',true);
  v_date_tokyo:=atlas.organization_membership_calendar_date_at_v1(
    setup_org,'2026-09-20 02:30:00+00'::timestamptz
  );

  if v_date_utc<>'2026-09-19'::date
     or v_date_tokyo<>'2026-09-19'::date then
    raise exception 'Membership civil date depends on session timezone: UTC %, Tokyo %.',
      v_date_utc,v_date_tokyo;
  end if;

  -- 8. Change is supersede + append; previous evidence remains.
  v_result:=atlas.set_organization_membership_calendar_context_internal_v1(
    setup_org,'America/Denver','organization_setup_actor_declaration',
    setup_user,null,'fixture context change','{"validation_fixture":true}'::jsonb
  );
  v_second:=(v_result->>'contextId')::uuid;

  if v_second is null or v_second=v_first then
    raise exception 'Context change did not append new durable identity.';
  end if;

  if not exists(
    select 1 from atlas.organization_membership_calendar_contexts
    where id=v_first and context_state='superseded' and superseded_at is not null
  ) or not exists(
    select 1 from atlas.organization_membership_calendar_contexts
    where id=v_second and context_state='active' and timezone_name='America/Denver'
  ) then
    raise exception 'Context change did not preserve superseded history plus one active row.';
  end if;

  select count(*)::integer into v_count
  from atlas.organization_membership_calendar_contexts
  where organization_id=setup_org and context_state='active';

  if v_count<>1 then
    raise exception 'Organization has % active Membership Calendar Contexts; expected one.',v_count;
  end if;

  -- 9. Superseded row cannot be reactivated or deleted.
  v_failed:=false;
  begin
    update atlas.organization_membership_calendar_contexts
    set context_state='active',superseded_at=null
    where id=v_first;
  exception when sqlstate '23514' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Superseded Membership Calendar Context was reactivated.';
  end if;

  v_failed:=false;
  begin
    delete from atlas.organization_membership_calendar_contexts where id=v_first;
  exception when sqlstate '55000' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Append-preserving Membership Calendar Context was deleted.';
  end if;

  -- 10. One-active structural invariant rejects a second direct active row.
  v_failed:=false;
  begin
    insert into atlas.organization_membership_calendar_contexts(
      organization_id,timezone_name,basis_kind,authority_evidence,metadata
    ) values (
      setup_org,'America/New_York','current_state_compatibility_adjudication',
      '{"validation_fixture":true}'::jsonb,'{"validation_fixture":true}'::jsonb
    );
  exception when unique_violation then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'One-active Membership Calendar Context invariant failed.';
  end if;

  -- 11. Root Principal may establish context only through exact root-governing participation.
  v_result:=atlas.set_organization_membership_calendar_context_internal_v1(
    root_org,'Europe/London','principal_root_governing_declaration',
    null,root_principal,'fixture root declaration','{"validation_fixture":true}'::jsonb
  );
  v_root:=(v_result->>'contextId')::uuid;

  if v_root is null
     or not exists(
       select 1
       from atlas.organization_membership_calendar_contexts c
       where c.id=v_root
         and c.established_by_principal_id=root_principal
         and c.established_by_person_id='ca200000-0000-4000-8000-000000000011'::uuid
         and c.authority_evidence->>'authorityKind'='principal_ledger_root_governing'
         and c.authority_evidence->>'principalLedgerAuthorityId'='ca230000-0000-4000-8000-000000000001'
         and c.authority_evidence->>'ledgerOrganizationParticipationId'='ca240000-0000-4000-8000-000000000001'
     ) then
    raise exception 'Root-governing declaration lacks exact authority evidence: %',v_result;
  end if;

  -- 12. An unrelated user cannot impersonate setup authority.
  v_failed:=false;
  begin
    perform atlas.set_organization_membership_calendar_context_internal_v1(
      missing_org,'America/New_York','organization_setup_actor_declaration',
      'ca300000-0000-4000-8000-000000000001'::uuid,null,
      'unauthorized fixture attempt','{"validation_fixture":true}'::jsonb
    );
  exception when sqlstate '42501' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Non-setup actor established Membership Calendar Context.';
  end if;

  -- 13. Phase A does not cut current authority helpers over yet.
  if pg_get_functiondef(
       'atlas.current_effective_organization_membership_v1(uuid)'::regprocedure
     ) ilike '%organization_membership_calendar_context%'
     or pg_get_functiondef(
       'atlas.is_organization_owner(uuid)'::regprocedure
     ) ilike '%organization_membership_calendar_context%'
     or pg_get_functiondef(
       'atlas.is_effective_organization_owner_v1(uuid)'::regprocedure
     ) ilike '%organization_membership_calendar_context%' then
    raise exception 'Phase A changed current Membership/owner authority helpers prematurely.';
  end if;

  if pg_get_functiondef(
       'atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%eligibility_begins_on is null%'
     or pg_get_functiondef(
       'atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%eligibility_ends_on is null%' then
    raise exception 'Phase A unexpectedly removed the interim bounded-Membership Endpoint fail-closed fence.';
  end if;
end;
$proof$;
