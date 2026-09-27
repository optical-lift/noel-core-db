-- Canonical fundraising contacts contract v1.
-- Structural assertions only; intended for the production-schema clone after migrations.

do $$
declare
  v_bad_columns integer;
  v_missing integer;
begin
  if to_regclass('atlas.fundraising_constituent_relationships') is null then
    raise exception 'fundraising_constituent_relationships missing';
  end if;

  select count(*) into v_bad_columns
  from information_schema.columns
  where table_schema='atlas'
    and table_name='fundraising_constituent_relationships'
    and lower(column_name) in (
      'name','display_name','donor_name','constituent_name','email','phone','address','address_line1','route_value'
    );
  if v_bad_columns<>0 then
    raise exception 'Fundraising constituent relationship must not copy names/contact routes.';
  end if;

  if not exists(
    select 1 from pg_constraint c
    where c.conrelid='atlas.fundraising_constituent_relationships'::regclass
      and pg_get_constraintdef(c.oid) like '%REFERENCES reality.entities(id)%'
  ) then
    raise exception 'Fundraising constituent relationships must reference canonical Reality entities.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='smart_contact_saved_search_run_items'
      and column_name='reality_entity_id'
  ) then
    raise exception 'Saved Smart Contact runs must carry reality_entity_id.';
  end if;

  if not exists(
    select 1 from information_schema.columns
    where table_schema='atlas' and table_name='contact_selection_packet_items'
      and column_name='reality_entity_id'
  ) then
    raise exception 'Contact selection packets must carry reality_entity_id.';
  end if;

  select count(*) into v_missing
  from (values
    ('smart_contact_reality_entity_internal_v2'),
    ('smart_contacts_search_service_v2'),
    ('smart_contacts_search_self_api_v2'),
    ('run_smart_contact_saved_search_service_v2'),
    ('run_smart_contact_saved_search_self_api_v2'),
    ('create_reality_contact_packet_from_saved_run_service_v2'),
    ('create_reality_contact_packet_from_saved_run_self_api_v2'),
    ('fundraising_entity_authorized_self_v1'),
    ('establish_fundraising_constituent_self_api_v1'),
    ('fundraising_constituents_self_api_v1'),
    ('fundraising_newsletter_audience_self_api_v1'),
    ('fundraising_constituent_accounting_activity_self_api_v1')
  ) expected(name)
  where not exists(
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas' and p.proname=expected.name
  );
  if v_missing<>0 then
    raise exception 'Canonical fundraising contact functions missing: %',v_missing;
  end if;

  if not exists(
    select 1 from pg_trigger t
    where t.tgrelid='atlas.accounting_journal_lines'::regclass
      and t.tgname='accounting_journal_line_canonical_subject_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Accounting canonical subject guard missing.';
  end if;

  if not exists(
    select 1 from pg_trigger t
    where t.tgrelid='atlas.contact_selection_packet_items'::regclass
      and t.tgname='contact_selection_packet_reality_identity_guard_v2'
      and not t.tgisinternal
  ) then
    raise exception 'Contact packet Reality identity guard missing.';
  end if;

  if has_table_privilege('authenticated','atlas.fundraising_constituent_relationships','INSERT')
     or has_table_privilege('authenticated','atlas.fundraising_constituent_relationships','UPDATE')
     or has_table_privilege('authenticated','atlas.fundraising_constituent_relationships','DELETE') then
    raise exception 'Authenticated role must not write fundraising constituent table directly.';
  end if;
end
$$;
