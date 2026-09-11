-- Atlas Organization Spend local-date semantics v1
-- Candidate follow-on to 20260911012500_atlas_organization_spend_kernel_v1.
-- `occurred_on` is the observed/local business date. `occurred_at`, when known,
-- is an exact instant. A PostgreSQL session-timezone cast must not be allowed to
-- redefine the observed business date.

do $migration$
declare
  v_constraint_name text;
begin
  select con.conname
  into v_constraint_name
  from pg_constraint con
  join pg_class rel on rel.oid=con.conrelid
  join pg_namespace nsp on nsp.oid=rel.relnamespace
  where nsp.nspname='atlas'
    and rel.relname='organization_spend_occurrences'
    and con.contype='c'
    and pg_get_constraintdef(con.oid) ilike '%occurred_at%date%occurred_on%'
  order by con.conname
  limit 1;

  if v_constraint_name is not null then
    execute format(
      'alter table atlas.organization_spend_occurrences drop constraint %I',
      v_constraint_name
    );
  end if;
end;
$migration$;

comment on column atlas.organization_spend_occurrences.occurred_on is
  'Observed/local business date of the Spend occurrence. This is authoritative as a date and is not derived from occurred_at using the database session timezone.';

comment on column atlas.organization_spend_occurrences.occurred_at is
  'Optional exact instant of the Spend occurrence when the source establishes one. It does not redefine occurred_on.';
