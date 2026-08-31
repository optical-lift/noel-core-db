BEGIN;

-- A withdrawal event is evidence about the immutable item snapshot being
-- withdrawn. Its generation therefore belongs to that item, while the
-- superseding generation (when any) is successor evidence. Normalize this at
-- the event boundary before relational custody constraints are evaluated.

create or replace function atlas.normalize_commitment_withdrawal_event_generation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_item_plan_id uuid;
  v_item_generation_id uuid;
  v_successor_generation_id uuid;
begin
  if new.event_kind <> 'item_withdrawn' or new.item_id is null then
    return new;
  end if;

  select i.plan_id,i.generation_id
  into v_item_plan_id,v_item_generation_id
  from atlas.commitment_items i
  where i.id=new.item_id;

  if v_item_plan_id is null then
    raise exception 'Withdrawn commitment item was not found.' using errcode='23503';
  end if;
  if new.plan_id is distinct from v_item_plan_id then
    raise exception 'Withdrawal event plan does not own commitment item.' using errcode='23503';
  end if;

  if new.generation_id is distinct from v_item_generation_id then
    v_successor_generation_id:=new.generation_id;
    new.generation_id:=v_item_generation_id;
    if v_successor_generation_id is not null then
      new.evidence:=coalesce(new.evidence,'{}'::jsonb)||jsonb_build_object(
        'successorGenerationId',v_successor_generation_id
      );
    end if;
  end if;

  return new;
end;
$function$;

create trigger commitment_events_withdrawal_generation_normalizer
before insert on atlas.commitment_events
for each row execute function atlas.normalize_commitment_withdrawal_event_generation_v1();

revoke all on function atlas.normalize_commitment_withdrawal_event_generation_v1() from public,anon,authenticated;
grant execute on function atlas.normalize_commitment_withdrawal_event_generation_v1() to service_role;

comment on function atlas.normalize_commitment_withdrawal_event_generation_v1() is
  'Commitment custody boundary: item_withdrawn belongs to the immutable item generation; any attempted successor generation is preserved as evidence rather than cross-wiring the event.';

COMMIT;
