-- Postconditions for Atlas Relationship Delivery Grant v1.
-- Runs only against the disposable production-schema clone.

do $$
declare
  v_person uuid;
  v_org_grant uuid;
  v_household_grant uuid;
  v_failed boolean;
begin
  if to_regclass('atlas.relationship_delivery_grants') is null
     or to_regclass('atlas.relationship_delivery_grant_contracts') is null then
    raise exception 'Relationship Delivery Grant relations are missing.';
  end if;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='relationship_delivery_grants'
      and c.relrowsecurity
  ) or not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='relationship_delivery_grant_contracts'
      and c.relrowsecurity
  ) then
    raise exception 'Relationship Delivery Grant tables must have RLS enabled.';
  end if;

  if has_table_privilege('anon','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('anon','atlas.relationship_delivery_grants','INSERT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_grants','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_grants','INSERT')
     or has_table_privilege('anon','atlas.relationship_delivery_grant_contracts','SELECT')
     or has_table_privilege('authenticated','atlas.relationship_delivery_grant_contracts','SELECT') then
    raise exception 'Relationship Delivery Grant tables widened browser privileges.';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='relationship_delivery_grants'
      and column_name in (
        'organization_id',
        'organization_membership_id',
        'employee_seat_id',
        'household_id',
        'household_member_id',
        'auth_user_id'
      )
  ) then
    raise exception 'Universal Relationship Delivery Grant was hard-coded to one relationship/account type.';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='atlas'
      and table_name='relationship_delivery_grants'
      and column_name='recipient_person_id'
      and is_nullable='NO'
  ) then
    raise exception 'Relationship Delivery Grant does not require canonical Person.';
  end if;

  insert into atlas.people(display_name,status,metadata)
  values(
    'Relationship Delivery Validation Person',
    'active',
    jsonb_build_object('source','relationship_delivery_grant_v1_validation')
  )
  returning id into v_person;

  -- Institutional pressure test: the universal table stores a source-owned
  -- membership reference without acquiring Organization-specific columns.
  insert into atlas.relationship_delivery_grants(
    recipient_person_id,
    issuer_domain,
    issuer_kind,
    issuer_id,
    relationship_domain,
    relationship_kind,
    relationship_id,
    lifecycle_state,
    valid_from,
    expires_at,
    provenance
  ) values (
    v_person,
    'organization',
    'organization',
    'organization:validation',
    'organization',
    'organization_membership',
    'membership:validation',
    'active',
    clock_timestamp(),
    clock_timestamp() + interval '1 day',
    jsonb_build_object('basis','institutional_pressure_test')
  )
  returning id into v_org_grant;

  insert into atlas.relationship_delivery_grant_contracts(
    grant_id, contract_kind, contract_key, contract_version
  ) values
    (v_org_grant,'projection','institution.worker_day.today',1),
    (v_org_grant,'response','institution.company_work.result',1);

  -- Household pressure test: same tables, no schema fork.
  insert into atlas.relationship_delivery_grants(
    recipient_person_id,
    issuer_domain,
    issuer_kind,
    issuer_id,
    relationship_domain,
    relationship_kind,
    relationship_id,
    lifecycle_state,
    provenance
  ) values (
    v_person,
    'household',
    'household',
    'household:validation',
    'household',
    'household_member',
    'household_member:validation',
    'active',
    jsonb_build_object('basis','household_pressure_test')
  )
  returning id into v_household_grant;

  insert into atlas.relationship_delivery_grant_contracts(
    grant_id, contract_kind, contract_key, contract_version
  ) values
    (v_household_grant,'projection','household.grocery.current',1),
    (v_household_grant,'response','household.grocery.result',1);

  if (
    select count(*)
    from atlas.relationship_delivery_grants
    where id in (v_org_grant,v_household_grant)
      and recipient_person_id=v_person
      and lifecycle_state='active'
  ) <> 2 then
    raise exception 'Cross-domain Relationship Delivery Grant pressure test failed.';
  end if;

  if (
    select count(*)
    from atlas.relationship_delivery_grant_contracts
    where grant_id in (v_org_grant,v_household_grant)
  ) <> 4 then
    raise exception 'Relationship Delivery contract assignments were not preserved.';
  end if;

  -- Grant validity windows must not permit an expiry before activation.
  v_failed := false;
  begin
    insert into atlas.relationship_delivery_grants(
      recipient_person_id,
      issuer_domain,
      issuer_kind,
      issuer_id,
      relationship_domain,
      relationship_kind,
      relationship_id,
      valid_from,
      expires_at
    ) values (
      v_person,
      'validation',
      'issuer',
      'issuer:invalid-window',
      'validation',
      'relationship',
      'relationship:invalid-window',
      clock_timestamp(),
      clock_timestamp() - interval '1 minute'
    );
  exception when check_violation then
    v_failed := true;
  end;

  if not v_failed then
    raise exception 'Relationship Delivery Grant accepted an invalid validity window.';
  end if;

  delete from atlas.relationship_delivery_grants
  where id in (v_org_grant,v_household_grant);
  delete from atlas.people where id=v_person;
end;
$$;
