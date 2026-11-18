-- Repair the original Work subject-pair seam, independently of placement.
-- Prior reviewed Household custody candidate already intended a Household branch.
-- Preserve every institutional subject pair and the existing signed exact-link guard.
begin;
do $preflight$
declare v_definition text;
begin
 select pg_get_constraintdef(c.oid) into v_definition from pg_constraint c
 where c.conrelid='atlas.work_item_context_links'::regclass
   and c.conname='work_item_context_links_subject_pair_v1' and c.contype='c' and c.convalidated;
 if v_definition is distinct from
  'CHECK ((((subject_domain = ''spatial''::text) AND (subject_kind = ANY (ARRAY[''zone''::text, ''place''::text, ''growing_object''::text]))) OR ((subject_domain = ''identity''::text) AND (subject_kind = ANY (ARRAY[''identity_subject''::text, ''external_relationship''::text]))) OR ((subject_domain = ''temporal''::text) AND (subject_kind = ''occurrence''::text))))'
 then raise exception 'Original subject pair changed; reconcile source before applying'; end if;
 if not exists(select 1 from pg_trigger
   where tgrelid='atlas.work_item_context_links'::regclass
    and tgname='z_guard_household_work_subject_link_v1'
    and tgfoid='atlas.guard_household_work_subject_link_v1()'::regprocedure
    and tgenabled='O' and not tgisinternal)
 then raise exception 'Required exact Household subject guard unavailable'; end if;
 if has_table_privilege('authenticated','atlas.work_item_context_links','INSERT')
 or has_table_privilege('authenticated','atlas.work_item_context_links','UPDATE')
 or has_table_privilege('anon','atlas.work_item_context_links','INSERT')
 then raise exception 'Private Work link write boundary not established'; end if;
end;
$preflight$;
alter table atlas.work_item_context_links
 drop constraint work_item_context_links_subject_pair_v1;
alter table atlas.work_item_context_links
 add constraint work_item_context_links_subject_pair_v1 check (
   (subject_domain='spatial' and subject_kind in ('zone','place','growing_object'))
   or (subject_domain='identity' and subject_kind in ('identity_subject','external_relationship'))
   or (subject_domain='temporal' and subject_kind='occurrence')
   or (household_id is not null and organization_id is null
      and subject_domain='household' and subject_kind='kernel_instance' and relation_kind='acts_on')
 );
commit;
