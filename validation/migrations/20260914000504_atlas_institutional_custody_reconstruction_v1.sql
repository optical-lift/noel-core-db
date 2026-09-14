-- Behavioral postconditions for Atlas Institutional Custody Reconstruction v1.
-- This tranche is additive: canonical/effective custody changes while historical rows remain physical compatibility evidence.

do $function$
declare
  v_elm_org uuid;
  v_fg_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
  v_fg_ledger uuid;
  v_carrier uuid;
  v_row record;
  v_failed boolean;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_fg_org from atlas.organizations where metadata->>'custody_reconstruction_key'='feast_guild_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';
  select id into v_fg_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='feast_guild_ledger_v1';

  if v_elm_org is null or v_fg_org is null or v_farm_ledger is null or v_venue_ledger is null or v_fg_ledger is null then
    raise exception 'Canonical custody graph identities were not established.';
  end if;

  if v_elm_org=v_fg_org or v_farm_ledger in (v_venue_ledger,v_fg_ledger) or v_venue_ledger=v_fg_ledger then
    raise exception 'Canonical custody identities collapsed.';
  end if;

  if exists (
    select 1 from atlas.organizations
    where id in (v_elm_org,v_fg_org)
      and stable_key in ('elm','elm_farm','feast_guild','elm_venue')
  ) or exists (
    select 1 from atlas.ledgers
    where id in (v_farm_ledger,v_venue_ledger,v_fg_ledger)
      and stable_key in ('elm','elm_farm','feast_guild','elm_venue')
  ) then
    raise exception 'Canonical identities use semantic names as stable identity.';
  end if;

  -- Historical compatibility carrier must be physically unchanged.
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Historical Organization carrier changed.';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Historical Ledger carrier changed.';
  end if;

  if not exists (
    select 1 from atlas.ledger_organization_participations
    where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and status='active'
  ) then
    raise exception 'Historical carrier participation changed before runtime cutover.';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities
    where principal_id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
      and ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and status='active'
  ) then
    raise exception 'Historical carrier authority changed before runtime cutover.';
  end if;

  -- New canonical authority is direct Principal -> Ledger authority.
  if (select count(*) from atlas.principal_ledger_authorities
      where principal_id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
        and ledger_id in (v_farm_ledger,v_venue_ledger,v_fg_ledger)
        and authority_kind='root_governing' and status='active') <> 3 then
    raise exception 'Lex does not hold all three canonical root authorities.';
  end if;

  if (select count(*) from atlas.ledger_organization_participations
      where organization_id=v_elm_org and ledger_id in (v_farm_ledger,v_venue_ledger) and status='active') <> 2 then
    raise exception 'Elm Organization does not participate in both Elm Ledgers.';
  end if;

  if (select count(*) from atlas.ledger_organization_participations
      where organization_id=v_fg_org and ledger_id=v_fg_ledger and status='active') <> 1 then
    raise exception 'Feast Guild participation missing.';
  end if;

  -- Compatibility carrier is explicit and relationally points at the forward graph.
  select id into v_carrier
  from atlas.institutional_custody_carriers
  where carrier_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and carrier_ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
    and carrier_kind='legacy_mixed_scope' and status='active';

  if v_carrier is null then raise exception 'Compatibility carrier record missing.'; end if;

  if (select count(*) from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier) <> 5 then
    raise exception 'Compatibility carrier target graph is incomplete.';
  end if;

  if not exists (select 1 from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier and target_key='elm_farm_organization' and canonical_organization_id=v_elm_org)
     or not exists (select 1 from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier and target_key='elm_farm_ledger' and canonical_organization_id=v_elm_org and canonical_ledger_id=v_farm_ledger)
     or not exists (select 1 from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier and target_key='elm_venue_ledger' and canonical_organization_id=v_elm_org and canonical_ledger_id=v_venue_ledger)
     or not exists (select 1 from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier and target_key='feast_guild_organization' and canonical_organization_id=v_fg_org)
     or not exists (select 1 from atlas.institutional_custody_carrier_targets where carrier_id=v_carrier and target_key='feast_guild_ledger' and canonical_organization_id=v_fg_org and canonical_ledger_id=v_fg_ledger) then
    raise exception 'Compatibility carrier targets do not match canonical graph.';
  end if;

  -- Physical Elm anchors are unchanged while effective custody is canonical Elm.
  if not exists (select 1 from atlas.organization_units where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='active')
     or not exists (select 1 from atlas.farms where id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid and status='active') then
    raise exception 'Elm physical anchors were rewritten.';
  end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','organization_units','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org or v_row.disposition<>'reassigned' or not v_row.from_adjudication then raise exception 'Elm Unit effective custody is wrong.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','farms','6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org or v_row.effective_ledger_id is distinct from v_farm_ledger then raise exception 'Elm Farm effective custody is wrong.'; end if;

  -- Anna durable identity stays physically historical but resolves to canonical Elm.
  if not exists (select 1 from atlas.organization_memberships where id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and person_id='998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid and active)
     or not exists (select 1 from atlas.organization_employee_seats where id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='active')
     or not exists (select 1 from atlas.organization_member_credentials where id='385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid)
     or not exists (select 1 from atlas.organization_positions where id='badd2192-28a7-4913-aa90-e7076cb419f5'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid)
     or not exists (select 1 from atlas.organization_position_appointments where id='1baf1031-cbe3-4520-9b5d-485bb5c9a59c'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) then
    raise exception 'Anna durable identity rows were rewritten.';
  end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','organization_memberships','4bda9631-07a6-43ae-9f51-4cb63d78c803','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org or v_row.disposition<>'reassigned' then raise exception 'Anna membership effective custody is wrong.'; end if;

  -- Representative Unit/FK evidence resolves without physical mutation.
  if not exists (select 1 from atlas.external_relationships where id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa20'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid)
     or not exists (select 1 from atlas.work_items where id='dddddddd-1000-4000-8000-dddddddd0001'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid)
     or not exists (select 1 from atlas.operational_routes where id='eeeeeeee-1000-4000-8000-eeeeeeee0001'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) then
    raise exception 'Representative Elm source rows were physically rewritten.';
  end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','external_relationships','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa20','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org then raise exception 'Relationship effective custody is wrong.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','work_items','dddddddd-1000-4000-8000-dddddddd0001','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org then raise exception 'Company Work effective custody is wrong.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','operational_routes','eeeeeeee-1000-4000-8000-eeeeeeee0001','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org then raise exception 'Route effective custody is wrong.'; end if;

  -- Six fixed-revision Ledger events remain byte-addressed historical rows but resolve to Elm Farm Ledger.
  if (select count(*) from atlas.organization_ledger_entries where id in (
      'cccccccc-1000-4000-8000-cccccccc0001'::uuid,'cccccccc-1000-4000-8000-cccccccc0002'::uuid,'cccccccc-1000-4000-8000-cccccccc0003'::uuid,
      'cccccccc-1000-4000-8000-cccccccc0004'::uuid,'cccccccc-1000-4000-8000-cccccccc0005'::uuid,'cccccccc-1000-4000-8000-cccccccc0006'::uuid)
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and revision in (8101,8102,8103,8104,8105,8106)) <> 6 then
    raise exception 'Historical Ledger entry identity/revision/custody changed.';
  end if;

  if (select count(*) from atlas.institutional_custody_adjudications a
      where a.subject_schema='atlas' and a.subject_table='organization_ledger_entries'
        and a.subject_key in (
          'cccccccc-1000-4000-8000-cccccccc0001','cccccccc-1000-4000-8000-cccccccc0002','cccccccc-1000-4000-8000-cccccccc0003',
          'cccccccc-1000-4000-8000-cccccccc0004','cccccccc-1000-4000-8000-cccccccc0005','cccccccc-1000-4000-8000-cccccccc0006')
        and a.disposition='reassigned' and a.canonical_organization_id=v_elm_org and a.canonical_ledger_id=v_farm_ledger) <> 6 then
    raise exception 'Historical Ledger entries do not resolve to Elm Farm Ledger.';
  end if;

  -- Waiting Room and owner-level portfolio work are archived only in effective custody.
  if not exists (select 1 from atlas.farms where id='f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='active') then
    raise exception 'Waiting Room physical farm was rewritten.';
  end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','tasks','aaaaaaaa-1000-4000-8000-aaaaaaaa0002','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'archived' or v_row.effective_organization_id is not null then raise exception 'Waiting Room task is not effectively archived.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','tasks','aaaaaaaa-1000-4000-8000-aaaaaaaa0003','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'archived' or v_row.effective_organization_id is not null then raise exception 'Owner portfolio task is not effectively archived.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','projects','bbbbbbbb-1000-4000-8000-bbbbbbbb0003','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'archived' then raise exception 'Owner portfolio project is not effectively archived.'; end if;

  -- Generic composition/Local state is explicitly not promoted to Elm.
  select * into v_row from atlas.effective_institutional_custody_v1('atlas','composition_runs','ffffffff-1000-4000-8000-ffffffff0001','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'archived' or v_row.effective_organization_id is not null then raise exception 'Generic composition was falsely promoted.'; end if;

  select * into v_row from atlas.effective_institutional_custody_v1('local_intel','recommendation_lenses','ffffffff-2000-4000-8000-ffffffff0001','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'archived' or v_row.effective_organization_id is not null then raise exception 'Generic recommendation lens was falsely promoted.'; end if;

  -- Inactive collaborator membership is a deliberate unresolved residual, not guessed into Elm.
  select * into v_row from atlas.effective_institutional_custody_v1('atlas','organization_memberships','8cc87ff8-f7d0-4dcc-86ae-ecc8cb84bc55','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.disposition<>'unresolved' or v_row.effective_organization_id is not null then raise exception 'Residual mixed-container membership was guessed into a canonical institution.'; end if;

  -- Communication source physical behavior and custody columns remain untouched.
  if not exists (
    select 1 from atlas.connected_sources
    where id='188291ac-3b08-429b-8ea1-a2bf3f3833ef'::uuid
      and custodian_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and authorization_state='connected'
      and granted_scopes=array['communication.capture']::text[]
      and capabilities='{"communicationSend":false,"communicationCapture":true}'::jsonb
      and last_sync_at='2026-09-13 13:21:24+00'::timestamptz
      and revoked_at is null
  ) or not exists (
    select 1 from atlas.connected_sources
    where id='238df033-5704-4404-bf34-a509f4e4d1c1'::uuid
      and custodian_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and authorization_state='pending'
      and granted_scopes=array['mail.read','mail.send']::text[]
      and capabilities='{"communicationSend":false,"communicationCapture":false}'::jsonb
      and last_sync_at is null and revoked_at is null
  ) then
    raise exception 'Communication source behavior/custody changed.';
  end if;

  select * into v_row from atlas.effective_institutional_custody_v1('atlas','connected_sources','188291ac-3b08-429b-8ea1-a2bf3f3833ef','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,null);
  if v_row.effective_organization_id is distinct from v_elm_org or v_row.disposition<>'reassigned' then raise exception 'Connected source effective custody is wrong.'; end if;

  -- Feast Guild remains a true clean room.
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
    raise exception 'Feast Guild clean-room boundary was violated.';
  end if;

  -- Canonical Elm contains only the intentionally new owner compatibility membership in this tranche.
  if (select count(*) from atlas.organization_memberships where organization_id=v_elm_org and active) <> 1
     or exists (select 1 from atlas.organization_employee_seats where organization_id=v_elm_org and status='active') then
    raise exception 'Physical Elm membership/seat state was manufactured beyond the authorized compatibility owner.';
  end if;

  -- Custody tables/resolver remain internal.
  if has_table_privilege('authenticated','atlas.institutional_custody_adjudications','select')
     or has_table_privilege('authenticated','atlas.institutional_custody_carriers','select')
     or has_table_privilege('authenticated','atlas.institutional_custody_carrier_targets','select')
     or has_function_privilege('authenticated','atlas.effective_institutional_custody_v1(text,text,text,uuid,uuid)','execute') then
    raise exception 'Browser role gained direct custody access.';
  end if;

  if not has_function_privilege('service_role','atlas.effective_institutional_custody_v1(text,text,text,uuid,uuid)','execute') then
    raise exception 'Service role cannot execute effective custody resolver.';
  end if;

  -- Production/runtime trigger contract remains intact: no user trigger is disabled.
  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where not t.tgisinternal and n.nspname in ('atlas','local_intel') and t.tgenabled='D'
  ) then
    raise exception 'A production/runtime user trigger is disabled after custody reconstruction.';
  end if;

  if not exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='external_relationships' and t.tgname='external_relationships_subject_org_guard_v1' and t.tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='commercial_orders' and t.tgname='commercial_orders_append_only_v1' and t.tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='communication_events' and t.tgname='communication_events_append_only' and t.tgenabled='O'
  ) or not exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='company_operating_knowledge' and t.tgname='company_operating_knowledge_established_semantics_guard' and t.tgenabled='O'
  ) then
    raise exception 'A governing runtime trigger changed state.';
  end if;

  -- Existing FK deferrability contract remains unchanged: one unrelated FK stays initially deferred.
  if (select count(*) from pg_constraint c join pg_class ch on ch.oid=c.conrelid join pg_namespace n on n.oid=ch.relnamespace
      where c.contype='f' and c.condeferrable and n.nspname in ('atlas','local_intel')) <> 1
     or not exists (
       select 1 from pg_constraint c join pg_class ch on ch.oid=c.conrelid join pg_namespace n on n.oid=ch.relnamespace
       where n.nspname='atlas' and ch.relname='planned_work_occurrences'
         and c.conname='planned_work_occurrences_released_task_id_fkey'
         and c.contype='f' and c.condeferrable and c.condeferred
     ) then
    raise exception 'Foreign-key deferrability changed during additive custody reconstruction.';
  end if;

  -- Adjudications are append-only in practice, not just by comment.
  v_failed:=false;
  begin
    update atlas.institutional_custody_adjudications
    set evidence_basis=evidence_basis
    where subject_schema='atlas' and subject_table='farms' and subject_key='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f';
  exception when sqlstate '55000' then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'Custody adjudication UPDATE was not blocked.'; end if;
end;
$function$;
