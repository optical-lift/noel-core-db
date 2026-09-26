-- Hardening for root Reality promotion v1.
-- The first responsibility-promotion slice is self-carried by the verified setup
-- sponsor. Delegating responsibility to another Person requires a later governed
-- acceptance/transfer membrane rather than piggybacking on setup sponsorship.

create or replace function reality.guard_implementation_setup_sponsor_responsibility_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','reality'
as $function$
begin
  if new.establishment_kind='implementation_setup_sponsor'
     and new.source_person_entity_id is distinct from new.carrier_person_entity_id then
    raise exception 'Implementation setup sponsorship may establish only responsibility carried by that verified setup sponsor.' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_implementation_setup_sponsor_responsibility_v1 on reality.responsibility_relations;
create trigger guard_implementation_setup_sponsor_responsibility_v1
before insert or update of carrier_person_entity_id,source_person_entity_id,establishment_kind
on reality.responsibility_relations
for each row execute function reality.guard_implementation_setup_sponsor_responsibility_v1();

comment on function reality.guard_implementation_setup_sponsor_responsibility_v1() is
  'Prevents setup-sponsor promotion from becoming an implicit delegation membrane. The first slice may establish only a responsibility carried by the verified setup sponsor themselves.';
