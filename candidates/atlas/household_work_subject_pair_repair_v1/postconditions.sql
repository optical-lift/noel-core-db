-- Disposable clone only, no production fixture writes.
begin;
do $test$
declare v_expression text; v_ok boolean; r record;
begin
 select pg_get_expr(c.conbin,c.conrelid) into v_expression from pg_constraint c
 where c.conrelid='atlas.work_item_context_links'::regclass
  and c.conname='work_item_context_links_subject_pair_v1' and c.convalidated;
 if v_expression is null then raise exception 'Subject pair not validated'; end if;
 for r in select * from (values
  ('spatial','zone','about',false,true),
  ('spatial','place','located_in',false,true),
  ('spatial','growing_object','acts_on',false,true),
  ('identity','identity_subject','for',false,true),
  ('identity','external_relationship','supports',false,true),
  ('temporal','occurrence','about',false,true),
  ('household','kernel_instance','acts_on',true,true),
  ('household','kernel_instance','acts_on',false,false),
  ('household','kernel_instance','about',true,false),
  ('household','household_space','acts_on',true,false),
  ('identity','kernel_instance','acts_on',true,false)
 ) as v(domain,kind,relation,is_household,expected) loop
  execute format('select (%s) is true from (select $1::text subject_domain,$2::text subject_kind,$3::text relation_kind,$4::uuid household_id,$5::uuid organization_id) s',v_expression)
  using r.domain,r.kind,r.relation,
   case when r.is_household then '00000000-0000-4000-8000-000000000001'::uuid else null::uuid end,
   case when not r.is_household then '00000000-0000-4000-8000-000000000002'::uuid else null::uuid end
  into v_ok;
  if v_ok is distinct from r.expected then
    raise exception 'Subject pair case failed: % / % / %',r.domain,r.kind,r.relation;
  end if;
 end loop;
 if not exists(select 1 from pg_trigger where tgrelid='atlas.work_item_context_links'::regclass
 and tgname='z_guard_household_work_subject_link_v1' and tgenabled='O'
 and tgfoid='atlas.guard_household_work_subject_link_v1()'::regprocedure)
 then raise exception 'Signed exact-subject guard missing'; end if;
 if has_table_privilege('authenticated','atlas.work_item_context_links','INSERT')
 or has_table_privilege('authenticated','atlas.work_item_context_links','UPDATE')
 then raise exception 'Direct signed link mutation exposed'; end if;
end;
$test$;
rollback;
