-- Canonical postcondition for Spend local-date semantics v1.
-- Runs only after the Spend kernel exists in the disposable clone baseline.

do $$
declare
  v_bad_constraint text;
begin
  if to_regclass('atlas.organization_spend_occurrences') is null then
    raise exception 'Spend kernel prerequisite is missing.';
  end if;

  select con.conname
  into v_bad_constraint
  from pg_constraint con
  where con.conrelid='atlas.organization_spend_occurrences'::regclass
    and con.contype='c'
    and pg_get_constraintdef(con.oid) ilike '%occurred_at%date%occurred_on%'
  limit 1;

  if v_bad_constraint is not null then
    raise exception 'Session-timezone date equality constraint still exists: %',v_bad_constraint;
  end if;

  if col_description('atlas.organization_spend_occurrences'::regclass,
      (select attnum from pg_attribute where attrelid='atlas.organization_spend_occurrences'::regclass and attname='occurred_on'))
      not ilike '%local business date%' then
    raise exception 'Spend occurred_on local-date authority comment is missing.';
  end if;
end;
$$;
