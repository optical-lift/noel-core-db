-- Behavioral postconditions for Atlas Institutional Custody Reconstruction v1.

do $validation$
declare
  v_elm_org uuid;
  v_fg_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
  v_fg_ledger uuid;
  v_failed boolean;
begin
  select id into v_elm_org
  from atlas.organizations
  where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_fg_org
  from atlas.organizations
  where metadata->>'custody_reconstruction_key'='feast_guild_organization_v1';
  select id into v_farm_ledger
  from atlas.ledgers
  where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger
  from atlas.ledgers
  where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';
  select id into v_fg_ledger
  from atlas.ledgers
  where metadata->>'custody_reconstruction_key'='feast_guild_ledger_v1';

  if v_elm_org is null or v_fg_org is null or v_farm_ledger is null or v_venue_ledger is null or v_fg_ledger is null then
    raise exception 'Canonical Elm / Venue / Feast Guild identities were not established.';
  end if;

  if v_elm_org=v_fg_org or v_farm_ledger=v_venue_ledger or v_farm_ledger=v_fg_ledger or v_venue_ledger=v_fg_ledger then
    raise exception 'Canonical institution or Ledger identities collapsed together.';
  end if;

  if not exists (
    select 1 from atlas.organizations o
    where o.id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and o.status='archived'
      and o.name='Legacy Principal Portfolio'
      and o.stable_key<>'feast_guild'
      and o.metadata->>'legacyStableKey'='feast_guild'
      and o.metadata->>'legacyName'='Feast Guild'
      and o.metadata->>'organization_kind'='legacy_principal_portfolio'
  ) then
    raise exception 'Historical mixed Organization was not safely archived/reclassified.';
  end if;

  if not exists (
    select 1 from atlas.ledgers l
    where l.id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and l.status='retired'
      and l.name='Legacy Principal Portfolio Ledger'
      and l.stable_key<>'feast_guild'
      and l.metadata->>'legacyStableKey'='feast_guild'
      and l.metadata->>'scope_state'='adjudicated_legacy_portfolio'
  ) then
    raise exception 'Historical mixed Ledger was not safely retired/reclassified.';
  end if;

  if exists (
    select 1 from atlas.ledger_organization_participations p
    where p.ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid and p.status='active'
  ) or exists (
    select 1 from atlas.principal_ledger_authorities a
    where a.ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid and a.status='active'
  ) then
    raise exception 'Legacy mixed Ledger still carries active participation or governing authority.';
  end if;

  if not exists (
    select 1 from atlas.principals p
    where p.id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
      and p.person_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid
      and p.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and p.status='active'
  ) then
    raise exception 'Lex Principal compatibility/history pointer changed unexpectedly.';
  end if;

  if not exists (
    select 1 from atlas.organizations o
    where o.id=v_elm_org and o.name='Elm Farm' and o.status='active'
      and o.stable_key ~ '^[0-9a-f]{32}$'
      and o.stable_key not in ('elm','elm_farm','feast_guild')
  ) then
    raise exception 'Elm Farm Organization is not an active opaque identity.';
  end if;

  if not exists (
    select 1 from atlas.organizations o
    where o.id=v_fg_org and o.name='Feast Guild' and o.status='active'
      and o.stable_key ~ '^[0-9a-f]{32}$'
      and o.stable_key<>'feast_guild'
      and o.metadata->>'cleanRoom'='true'
  ) then
    raise exception 'Feast Guild Organization is not a fresh opaque clean-room identity.';
  end if;

  if (select count(*) from atlas.ledgers l where l.id in (v_farm_ledger,v_venue_ledger,v_fg_ledger) and l.status='active' and l.stable_key ~ '^[0-9a-f]{32}$')<>3 then
    raise exception 'New Ledgers are not distinct active opaque identities.';
  end if;

  if not exists (select 1 from atlas.ledgers where id=v_farm_ledger and name='Elm Farm')
     or not exists (select 1 from atlas.ledgers where id=v_venue_ledger and name='Elm Venue')
     or not exists (select 1 from atlas.ledgers where id=v_fg_ledger and name='Feast Guild') then
    raise exception 'Canonical Ledger labels are incorrect.';
  end if;

  if (select count(*) from atlas.principal_ledger_authorities a
      where a.principal_id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
        and a.ledger_id in (v_farm_ledger,v_venue_ledger,v_fg_ledger)
        and a.authority_kind='root_governing' and a.status='active')<>3 then
    raise exception 'Lex does not hold root authority across all three canonical Ledgers.';
  end if;

  if (select count(*) from atlas.ledger_organization_participations p
      where p.organization_id=v_elm_org and p.status='active')<>2 then
    raise exception 'Elm Farm Organization must participate in exactly two active canonical Ledgers.';
  end if;

  if not exists (
    select 1 from atlas.ledger_organization_participations p
    where p.organization_id=v_elm_org and p.ledger_id=v_farm_ledger
      and p.status='active' and p.is_compatibility_primary
  ) or not exists (
    select 1 from atlas.ledger_organization_participations p
    where p.organization_id=v_elm_org and p.ledger_id=v_venue_ledger
      and p.status='active' and not p.is_compatibility_primary
  ) then
    raise exception 'Elm Farm / Venue participation graph is incorrect.';
  end if;

  if (select count(*) from atlas.ledger_organization_participations p
      where p.organization_id=v_fg_org and p.status='active')<>1
     or not exists (
       select 1 from atlas.ledger_organization_participations p
       where p.organization_id=v_fg_org and p.ledger_id=v_fg_ledger
         and p.status='active' and p.is_compatibility_primary
     ) then
    raise exception 'Feast Guild must participate only in its clean-room Ledger.';
  end if;

  -- Feast Guild starts genuinely empty except its institutional identity, participation, and Lex authority.
  if exists (select 1 from atlas.organization_memberships where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_employee_seats where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_units where organization_id=v_fg_org)
     or exists (select 1 from atlas.farms where organization_id=v_fg_org)
     or exists (select 1 from atlas.identity_subjects where organization_id=v_fg_org)
     or exists (select 1 from atlas.external_relationships where organization_id=v_fg_org)
     or exists (select 1 from atlas.communication_endpoints where organization_id=v_fg_org)
     or exists (select 1 from atlas.tasks where organization_id=v_fg_org)
     or exists (select 1 from atlas.projects where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_ledger_entries where organization_id=v_fg_org) then
    raise exception 'Feast Guild inherited historical operating reality.';
  end if;

  -- Elm's preserved operating anchors keep their identities while changing canonical Organization custody.
  if not exists (
    select 1 from atlas.organization_units
    where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid and organization_id=v_elm_org and status='active'
  ) then
    raise exception 'Elm Unit identity was not preserved into canonical Elm.';
  end if;

  if not exists (
    select 1 from atlas.farms
    where id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid and organization_id=v_elm_org and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  ) then
    raise exception 'Elm Farm identity was not preserved into canonical Elm.';
  end if;

  if not exists (
    select 1 from atlas.tasks where id='aaaaaaaa-1000-4000-8000-aaaaaaaa0001'::uuid
      and organization_id=v_elm_org and farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  ) or not exists (
    select 1 from atlas.projects where id='bbbbbbbb-1000-4000-8000-bbbbbbbb0001'::uuid
      and organization_id=v_elm_org and farm_id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  ) then
    raise exception 'Explicit Elm task/project identities did not move to canonical Elm.';
  end if;

  -- Waiting Room stays historical and is archived, not promoted into a canonical institution.
  if not exists (
    select 1 from atlas.organization_units where id='999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='archived'
  ) or not exists (
    select 1 from atlas.farms where id='f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='archived'
  ) or not exists (
    select 1 from atlas.projects where id='bbbbbbbb-1000-4000-8000-bbbbbbbb0002'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Waiting Room test scope was not preserved as archived historical evidence.';
  end if;

  if not exists (
    select 1 from atlas.institutional_custody_adjudications a
    where a.subject_table='projects' and a.subject_key='bbbbbbbb-1000-4000-8000-bbbbbbbb0002'
      and a.disposition='archived' and a.evidence_basis='waiting_room_test_scope'
  ) then
    raise exception 'Waiting Room project lacks archive adjudication.';
  end if;

  -- Owner-level work stays in the legacy portfolio container and is explicitly archived.
  if not exists (
    select 1 from atlas.tasks where id='aaaaaaaa-1000-4000-8000-aaaaaaaa0003'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and farm_id is null
  ) or not exists (
    select 1 from atlas.projects where id='bbbbbbbb-1000-4000-8000-bbbbbbbb0003'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and farm_id is null
  ) then
    raise exception 'Owner-level historical work was incorrectly promoted.';
  end if;

  if not exists (
    select 1 from atlas.institutional_custody_adjudications a
    where a.subject_table='tasks' and a.subject_key='aaaaaaaa-1000-4000-8000-aaaaaaaa0003'
      and a.disposition='archived' and a.evidence_basis='owner_level_portfolio_work'
  ) or not exists (
    select 1 from atlas.institutional_custody_adjudications a
    where a.subject_table='projects' and a.subject_key='bbbbbbbb-1000-4000-8000-bbbbbbbb0003'
      and a.disposition='archived' and a.evidence_basis='owner_level_portfolio_work'
  ) then
    raise exception 'Owner-level historical work lacks archive adjudications.';
  end if;

  -- Six Berry Walk entries preserve ID + revision but now belong to Elm Farm Ledger.
  if (select count(*) from atlas.organization_ledger_entries e
      where e.id in (
        'cccccccc-1000-4000-8000-cccccccc0001'::uuid,
        'cccccccc-1000-4000-8000-cccccccc0002'::uuid,
        'cccccccc-1000-4000-8000-cccccccc0003'::uuid,
        'cccccccc-1000-4000-8000-cccccccc0004'::uuid,
        'cccccccc-1000-4000-8000-cccccccc0005'::uuid,
        'cccccccc-1000-4000-8000-cccccccc0006'::uuid
      ) and e.organization_id=v_elm_org and e.ledger_id=v_farm_ledger
        and e.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid)<>6 then
    raise exception 'Historical Elm Ledger entries did not retain identity while moving to Elm Farm Ledger.';
  end if;

  if not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0001'::uuid and revision=8101)
     or not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0002'::uuid and revision=8102)
     or not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0003'::uuid and revision=8103)
     or not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0004'::uuid and revision=8104)
     or not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0005'::uuid and revision=8105)
     or not exists (select 1 from atlas.organization_ledger_entries where id='cccccccc-1000-4000-8000-cccccccc0006'::uuid and revision=8106) then
    raise exception 'Historical Elm Ledger entry revisions changed.';
  end if;

  if (select count(*) from atlas.institutional_custody_adjudications a
      where a.subject_table='organization_ledger_entries'
        and a.subject_key like 'cccccccc-1000-4000-8000-cccccccc000%'
        and a.disposition='reassigned' and a.canonical_organization_id=v_elm_org and a.canonical_ledger_id=v_farm_ledger)<>6 then
    raise exception 'Historical Elm Ledger entries lack canonical custody adjudications.';
  end if;

  -- Anna keeps the same institutional identities and is the only active Elm employee seat.
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid
      and m.organization_id=v_elm_org and m.person_id='998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid and m.active
  ) then
    raise exception 'Anna membership identity/custody was not preserved.';
  end if;

  if (select count(*) from atlas.organization_employee_seats s where s.organization_id=v_elm_org and s.status='active')<>1
     or not exists (
       select 1 from atlas.organization_employee_seats s
       where s.id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid
         and s.organization_id=v_elm_org
         and s.organization_membership_id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid
         and s.status='active'
     ) then
    raise exception 'Anna is not the sole active Elm employee seat.';
  end if;

  if not exists (
    select 1 from atlas.organization_member_credentials c
    where c.id='385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid
      and c.organization_id=v_elm_org and c.issued_by_organization_id=v_elm_org
      and c.auth_user_id='21436a28-40fd-4914-8015-a248d0dca14e'::uuid and c.status='active'
  ) then
    raise exception 'Anna institutional credential identity/custody was not preserved.';
  end if;

  if not exists (
    select 1 from atlas.organization_positions p
    where p.id='badd2192-28a7-4913-aa90-e7076cb419f5'::uuid
      and p.organization_id=v_elm_org and p.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and p.display_title='Farm Steward' and p.status='active'
  ) or not exists (
    select 1 from atlas.organization_position_appointments a
    where a.id='1baf1031-cbe3-4520-9b5d-485bb5c9a59c'::uuid
      and a.organization_id=v_elm_org and a.position_id='badd2192-28a7-4913-aa90-e7076cb419f5'::uuid
      and a.organization_membership_id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid and a.status='active'
  ) then
    raise exception 'Anna Farm Steward structure did not preserve identity.';
  end if;

  if (select count(*) from atlas.organization_responsibilities r where r.organization_id=v_elm_org and r.status='active')<>5 then
    raise exception 'Elm responsibility identities did not move intact.';
  end if;

  if not exists (
    select 1 from atlas.institutional_custody_adjudications a
    where a.subject_table='organization_responsibilities'
      and a.subject_key='d9a382c4-cbde-4b03-b8be-cf0465035bf4'
      and a.canonical_ledger_id=v_venue_ledger
  ) then
    raise exception 'Venue preparation was not explicitly adjudicated to Elm Venue Ledger.';
  end if;

  -- Elm endpoint/source custody moves without changing communication behavior.
  if not exists (
    select 1 from atlas.communication_endpoints e
    where e.id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
      and e.organization_id=v_elm_org and e.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and e.address_normalized='hello@elmfarm.co' and e.endpoint_state='active'
  ) then
    raise exception 'Elm communication endpoint custody did not move intact.';
  end if;

  if not exists (
    select 1 from atlas.connected_sources s
    where s.id='188291ac-3b08-429b-8ea1-a2bf3f3833ef'::uuid
      and s.custodian_organization_id=v_elm_org
      and s.custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and s.authorization_state='connected'
      and s.capabilities='{"communicationSend":false,"communicationCapture":true}'::jsonb
  ) or not exists (
    select 1 from atlas.connected_sources s
    where s.id='238df033-5704-4404-bf34-a509f4e4d1c1'::uuid
      and s.custodian_organization_id=v_elm_org
      and s.custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and s.authorization_state='pending'
      and s.last_sync_at is null
      and s.capabilities='{"communicationSend":false,"communicationCapture":false}'::jsonb
  ) then
    raise exception 'Communication source capture/send/authorization state changed during custody reconstruction.';
  end if;

  -- Elm institutional identity/customer evidence follows Elm; Feast Guild receives none of it.
  if not exists (
    select 1 from atlas.identity_subjects s where s.id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10'::uuid and s.organization_id=v_elm_org
  ) or not exists (
    select 1 from atlas.external_relationships r where r.id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa20'::uuid
      and r.organization_id=v_elm_org and r.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  ) then
    raise exception 'Elm identity/customer evidence did not move to canonical Elm.';
  end if;

  -- Only current Elm profiles are redirected; inactive historical collaborators remain on the archived portfolio container.
  if not exists (select 1 from atlas.user_profiles where user_id='4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid and default_organization_id=v_elm_org)
     or not exists (select 1 from atlas.user_profiles where user_id='21436a28-40fd-4914-8015-a248d0dca14e'::uuid and default_organization_id=v_elm_org)
     or not exists (select 1 from atlas.user_profiles where user_id='f496b283-795e-4c3e-b2ea-677989c9a235'::uuid and default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid)
     or not exists (select 1 from atlas.user_profiles where user_id='b5e4014b-8fc6-4733-9c89-e158f9dcc341'::uuid and default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) then
    raise exception 'User profile custody defaults are incorrect.';
  end if;

  if not exists (
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_elm_org and m.user_id='4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid
      and m.role='owner' and m.active
  ) then
    raise exception 'Lex compatibility owner membership for current Elm read surfaces is missing.';
  end if;

  if exists (
    select 1 from atlas.organization_employee_seats s
    join atlas.organization_memberships m on m.id=s.organization_membership_id
    where s.organization_id=v_elm_org and m.user_id='4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid
  ) then
    raise exception 'Lex was incorrectly made an Elm employee.';
  end if;

  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id='427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid
      and m.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and not m.active
  ) then
    raise exception 'Historical Lex owner membership was not preserved/inactivated.';
  end if;

  -- Custody evidence is sealed and append-only.
  if has_table_privilege('anon','atlas.institutional_custody_adjudications','SELECT')
     or has_table_privilege('authenticated','atlas.institutional_custody_adjudications','SELECT') then
    raise exception 'Browser roles can directly read custody adjudications.';
  end if;

  v_failed := false;
  begin
    update atlas.institutional_custody_adjudications
    set evidence_basis='should_not_change'
    where subject_schema='atlas' and subject_table='organizations'
      and subject_key='818b9a23-65e9-4198-b86c-9496ba548642';
  exception when sqlstate '55000' then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Custody adjudication UPDATE was not rejected.';
  end if;

  v_failed := false;
  begin
    delete from atlas.institutional_custody_adjudications
    where subject_schema='atlas' and subject_table='organizations'
      and subject_key='818b9a23-65e9-4198-b86c-9496ba548642';
  exception when sqlstate '55000' then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Custody adjudication DELETE was not rejected.';
  end if;

  if exists (
    select 1 from pg_constraint c
    where c.contype='f' and c.confrelid='atlas.organization_units'::regclass
      and array_length(c.conkey,1)=2 and c.condeferrable
  ) then
    raise exception 'Temporary Organization Unit FK deferral leaked into durable schema.';
  end if;
end;
$validation$;
