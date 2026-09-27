-- Mixed-source bookkeeping intake hardening v1
--
-- Enforce the custody boundaries structurally, not only through service functions.
-- Source transaction identity may refresh to a newer observation, but source identity itself
-- is immutable. Reviews, allocations, and promotion bridges are append-only history.

create or replace function atlas.guard_financial_source_transaction_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_first_source_id uuid;
  v_first_kind text;
  v_first_key text;
  v_current_source_id uuid;
  v_current_kind text;
  v_current_key text;
begin
  select observation.connected_source_id,observation.provider_object_kind,observation.provider_object_key
  into v_first_source_id,v_first_kind,v_first_key
  from atlas.connected_source_observations observation
  where observation.id=new.first_observation_id;

  select observation.connected_source_id,observation.provider_object_kind,observation.provider_object_key
  into v_current_source_id,v_current_kind,v_current_key
  from atlas.connected_source_observations observation
  where observation.id=new.current_observation_id;

  if v_first_source_id is null or v_current_source_id is null
     or v_first_source_id<>new.connected_source_id
     or v_current_source_id<>new.connected_source_id
     or v_first_kind<>'financial_transaction'
     or v_current_kind<>'financial_transaction'
     or v_first_key<>new.provider_transaction_key
     or v_current_key<>new.provider_transaction_key then
    raise exception 'Financial transaction observations must match the stable connected-source transaction identity.' using errcode='23514';
  end if;

  if tg_op='UPDATE' and (
    new.connected_source_id is distinct from old.connected_source_id
    or new.provider_transaction_key is distinct from old.provider_transaction_key
    or new.first_observation_id is distinct from old.first_observation_id
  ) then
    raise exception 'Financial source transaction identity and first observation are immutable.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

revoke all on function atlas.guard_financial_source_transaction_v1() from public, anon, authenticated;

drop trigger if exists financial_source_transactions_guard_v1 on atlas.financial_source_transactions;
create trigger financial_source_transactions_guard_v1
before insert or update on atlas.financial_source_transactions
for each row execute function atlas.guard_financial_source_transaction_v1();

create or replace function atlas.prevent_financial_source_review_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  raise exception 'Financial transaction review history is append-only.' using errcode='55000';
end;
$$;

revoke all on function atlas.prevent_financial_source_review_history_mutation_v1() from public, anon, authenticated;

drop trigger if exists financial_source_transaction_review_history_immutable_v1 on atlas.financial_source_transaction_review_events;
create trigger financial_source_transaction_review_history_immutable_v1
before update or delete on atlas.financial_source_transaction_review_events
for each row execute function atlas.prevent_financial_source_review_history_mutation_v1();

drop trigger if exists financial_source_transaction_allocations_history_immutable_v1 on atlas.financial_source_transaction_allocations;
create trigger financial_source_transaction_allocations_history_immutable_v1
before update or delete on atlas.financial_source_transaction_allocations
for each row execute function atlas.prevent_financial_source_review_history_mutation_v1();

drop trigger if exists financial_source_transaction_promotions_history_immutable_v1 on atlas.financial_source_transaction_spend_promotions;
create trigger financial_source_transaction_promotions_history_immutable_v1
before update or delete on atlas.financial_source_transaction_spend_promotions
for each row execute function atlas.prevent_financial_source_review_history_mutation_v1();

create or replace function atlas.guard_financial_source_review_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_current_observation_id uuid;
begin
  select transaction.current_observation_id
  into v_current_observation_id
  from atlas.financial_source_transactions transaction
  where transaction.id=new.financial_transaction_id;

  if v_current_observation_id is null or new.source_observation_id<>v_current_observation_id then
    raise exception 'A financial transaction review must snapshot the transaction current source observation.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_financial_source_review_event_v1() from public, anon, authenticated;

drop trigger if exists financial_source_transaction_review_event_guard_v1 on atlas.financial_source_transaction_review_events;
create trigger financial_source_transaction_review_event_guard_v1
before insert on atlas.financial_source_transaction_review_events
for each row execute function atlas.guard_financial_source_review_event_v1();

comment on function atlas.guard_financial_source_transaction_v1() is
  'Prevents normalized financial transaction identity from drifting away from its connected-source observations while permitting the current observation and normalized facts to refresh together.';
comment on function atlas.prevent_financial_source_review_history_mutation_v1() is
  'Makes financial transaction review, allocation, and Spend-promotion history append-only.';
