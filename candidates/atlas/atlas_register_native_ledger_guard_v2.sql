begin;

-- Repair Build 5 C1 operating-register establishment for native Ledger overlays.
-- atlas.ledgers.organization_id is a legacy nullable field. The authoritative
-- association is atlas.ledger_organization_participations, which the owner
-- RPC already validates. Preserve that authority boundary in the row guard.
create or replace function atlas.guard_operating_register_identity_v1()
returns trigger language plpgsql volatile security invoker set search_path to ''
as $fn$
begin
  if not exists(
    select 1
    from atlas.ledger_organization_participations lop
    join atlas.ledgers al on al.id=lop.ledger_id and al.status='active'
    join ledger.ledgers nl on nl.id=al.id
    where lop.ledger_id=new.ledger_id
      and lop.organization_id=new.organization_id
      and lop.status='active'
      and lop.ended_at is null
      and lop.participation_kind in ('governing','operating')
      and nl.ledger_state='active'
      and nl.retired_at is null
  ) or not exists (
    select 1 from atlas.work_requirements w
    where w.id=new.requirement_id
      and w.organization_id=new.organization_id
      and w.source_object_type='company_work_operating_register'
      and w.source_object_id=new.id
      and w.state='active'
  ) then
    raise exception 'One exact participating native Ledger and one source-matched canonical requirement required'
      using errcode='23514';
  end if;
  return new;
end
$fn$;

-- No table/RLS/grant expansion, task creation, recurrence or work allocation.
-- Existing immutable-identity trigger continues to invoke this guard.
revoke all on function atlas.guard_operating_register_identity_v1()
  from public,anon,authenticated;

commit;
