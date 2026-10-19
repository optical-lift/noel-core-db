-- Disposable-schema validation for the native Ledger participation guard.
do $post$
declare
  v_source text;
begin
  select pg_get_functiondef('atlas.guard_operating_register_identity_v1()'::regprocedure)
    into v_source;
  if position('ledger_organization_participations' in v_source)=0
    or position('lop.ledger_id=new.ledger_id' in v_source)=0
    or position('lop.organization_id=new.organization_id' in v_source)=0
    or position('lop.participation_kind' in v_source)=0
    or position('w.source_object_id=new.id' in v_source)=0
    or position('al.organization_id' in v_source)>0 then
    raise exception 'Operating register must require exact native participation and preserved requirement source match';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid='atlas.company_work_operating_register_entries'::regclass
      and tgname='operating_register_identity_scope_v1'
      and not tgisinternal
      and tgfoid='atlas.guard_operating_register_identity_v1()'::regprocedure
  ) then
    raise exception 'Operating-register immutable identity trigger missing';
  end if;
  if has_function_privilege('anon','atlas.guard_operating_register_identity_v1()','EXECUTE')
    or has_table_privilege('authenticated','atlas.company_work_operating_register_entries','INSERT')
    or has_table_privilege('anon','atlas.company_work_operating_register_entries','SELECT') then
    raise exception 'Register guard or table privilege broadened';
  end if;
  if exists (
    select 1 from pg_class
    where oid='atlas.company_work_operating_register_entries'::regclass
      and not relrowsecurity
  ) then
    raise exception 'Operating-register RLS disabled';
  end if;
end
$post$;
