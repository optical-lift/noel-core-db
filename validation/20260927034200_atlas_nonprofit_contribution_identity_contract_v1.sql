-- Nonprofit contribution identity contract v1.
do $$
declare
  v_bad_columns integer;
  v_missing integer;
begin
  if to_regclass('atlas.fundraising_contributions') is null
     or to_regclass('atlas.fundraising_pledges') is null
     or to_regclass('atlas.fundraising_grant_awards') is null then
    raise exception 'Nonprofit fundraising financial identity tables missing.';
  end if;

  select count(*) into v_bad_columns
  from information_schema.columns
  where table_schema='atlas'
    and table_name in ('fundraising_contributions','fundraising_pledges','fundraising_grant_awards')
    and lower(column_name) in (
      'donor_name','contributor_name','funder_name','name','email','phone','address','address_line1','contact_name'
    );
  if v_bad_columns<>0 then
    raise exception 'Fundraising financial records must not copy donor/funder identity fields.';
  end if;

  if not exists(
    select 1 from pg_constraint c
    where c.conrelid='atlas.fundraising_contributions'::regclass
      and pg_get_constraintdef(c.oid) like '%contributor_entity_id%REFERENCES reality.entities(id)%'
  ) then raise exception 'Contribution contributor_entity_id must reference Reality.'; end if;

  if not exists(
    select 1 from pg_constraint c
    where c.conrelid='atlas.fundraising_pledges'::regclass
      and pg_get_constraintdef(c.oid) like '%contributor_entity_id%REFERENCES reality.entities(id)%'
  ) then raise exception 'Pledge contributor_entity_id must reference Reality.'; end if;

  if not exists(
    select 1 from pg_constraint c
    where c.conrelid='atlas.fundraising_grant_awards'::regclass
      and pg_get_constraintdef(c.oid) like '%funder_entity_id%REFERENCES reality.entities(id)%'
  ) then raise exception 'Grant funder_entity_id must reference Reality.'; end if;

  select count(*) into v_missing
  from (values
    ('record_fundraising_contribution_self_api_v1'),
    ('record_fundraising_pledge_self_api_v1'),
    ('record_fundraising_grant_award_self_api_v1'),
    ('fundraising_constituent_financial_history_self_api_v1'),
    ('fundraising_constituent_profile_self_api_v1'),
    ('guard_fundraising_financial_fact_immutability_v1'),
    ('guard_fundraising_financial_state_transition_v1')
  ) expected(name)
  where not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.proname=expected.name
  );
  if v_missing<>0 then
    raise exception 'Nonprofit fundraising identity functions missing: %',v_missing;
  end if;

  if has_table_privilege('authenticated','atlas.fundraising_contributions','INSERT')
     or has_table_privilege('authenticated','atlas.fundraising_pledges','INSERT')
     or has_table_privilege('authenticated','atlas.fundraising_grant_awards','INSERT') then
    raise exception 'Authenticated role must not write fundraising financial tables directly.';
  end if;

  if not exists(
    select 1 from pg_trigger t
    where t.tgrelid='atlas.fundraising_contributions'::regclass
      and t.tgname='fundraising_contributions_immutability_guard_v1'
      and not t.tgisinternal
  ) then raise exception 'Contribution immutability guard missing.'; end if;

  if exists(
    select 1
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'record_fundraising_contribution_self_api_v1',
        'record_fundraising_pledge_self_api_v1',
        'record_fundraising_grant_award_self_api_v1'
      )
      and lower(pg_get_functiondef(p.oid)) like '%post_accounting_journal%'
  ) then
    raise exception 'Fundraising identity establishment must not post accounting journal entries.';
  end if;
end
$$;
