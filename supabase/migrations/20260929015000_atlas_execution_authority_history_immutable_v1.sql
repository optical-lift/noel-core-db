-- Execution Authority history is append-only.
-- The initial chain guard freezes coordinates across events; this tightening also
-- prevents mutation of an already-recorded event, including a one-event chain.

create or replace function atlas.enforce_execution_authority_chain_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    raise exception 'Execution Authority history is append-only; record a new authority event instead of updating history.'
      using errcode='55000';
  end if;

  if exists(
    select 1
    from atlas.execution_authority_history h
    where h.authority_id=new.authority_id
      and (
        h.person_entity_id<>new.person_entity_id
        or h.institution_entity_id<>new.institution_entity_id
        or h.responsibility_entity_id<>new.responsibility_entity_id
        or h.target_entity_id<>new.target_entity_id
        or h.operation_key<>new.operation_key
        or h.authority_valid_from<>new.authority_valid_from
        or h.authority_valid_until is distinct from new.authority_valid_until
        or h.carrier_kind<>new.carrier_kind
        or h.carrier_id<>new.carrier_id
      )
  ) then
    raise exception 'Execution authority history cannot change canonical coordinates, authority window, or carrier identity within one authority_id.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

comment on function atlas.enforce_execution_authority_chain_v1() is
  'Append-only guard for Execution Authority history. State changes are new events; one authority_id cannot migrate across canonical identity, jurisdiction, operation, time window, or carrier identity.';
