-- Run only in a disposable schema clone after the candidate is applied.
do $$
declare
  src text;
begin
  select pg_get_functiondef(oid) into src
  from pg_proc
  where oid = to_regprocedure('atlas.release_eligible_work_without_weed_physical_gate_v1(uuid,date,integer)');
  if src is null
     or position('releaseHoldReason' in src)=0
     or position('unresolved_organization' in src)=0
     or position('invalidOrganizationHeld' in src)=0
     or position('from atlas.organizations org' in src)=0 then
    raise exception 'Release hold candidate absent or incomplete';
  end if;
  if not exists(select 1 from pg_constraint where conname='tasks_organization_id_fkey') then
    raise exception 'Task organization foreign key must remain enforced';
  end if;
end $$;
