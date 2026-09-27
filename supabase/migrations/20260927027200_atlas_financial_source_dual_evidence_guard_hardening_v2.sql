-- Atlas financial source dual-evidence guard hardening v2
--
-- V1 connector-backed rows and V2 account-evidence-backed rows share the same stable
-- transaction/review tables. The original V1 guards therefore must validate whichever
-- evidence path the row actually uses rather than requiring connected-source observations.

create or replace function atlas.guard_financial_source_transaction_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_first_source_id uuid;
  v_first_kind text;
  v_first_key text;
  v_current_source_id uuid;
  v_current_kind text;
  v_current_key text;
  v_first_evidence atlas.financial_source_evidence_observations%rowtype;
  v_current_evidence atlas.financial_source_evidence_observations%rowtype;
begin
  if new.financial_source_account_id is not null then
    select * into v_first_evidence
    from atlas.financial_source_evidence_observations observation
    where observation.id=new.first_financial_evidence_observation_id;

    select * into v_current_evidence
    from atlas.financial_source_evidence_observations observation
    where observation.id=new.current_financial_evidence_observation_id;

    if v_first_evidence.id is null or v_current_evidence.id is null
       or v_first_evidence.financial_source_account_id<>new.financial_source_account_id
       or v_current_evidence.financial_source_account_id<>new.financial_source_account_id
       or v_first_evidence.observation_kind<>'financial_transaction'
       or v_current_evidence.observation_kind<>'financial_transaction'
       or v_first_evidence.source_object_key<>new.provider_transaction_key
       or v_current_evidence.source_object_key<>new.provider_transaction_key then
      raise exception 'Financial transaction evidence observations must match the stable financial account transaction identity.' using errcode='23514';
    end if;

    if tg_op='UPDATE' and (
      new.financial_source_account_id is distinct from old.financial_source_account_id
      or new.provider_transaction_key is distinct from old.provider_transaction_key
      or new.first_financial_evidence_observation_id is distinct from old.first_financial_evidence_observation_id
    ) then
      raise exception 'Financial account transaction identity and first evidence observation are immutable.' using errcode='23514';
    end if;

    new.updated_at:=now();
    return new;
  end if;

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
    raise exception 'Connected-source financial transaction identity and first observation are immutable.' using errcode='23514';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

comment on function atlas.guard_financial_source_transaction_v1() is
  'Guards the shared stable financial transaction table across connector-backed V1 and account-evidence-backed V2 paths while preserving immutable source identity.';

create or replace function atlas.guard_financial_source_review_event_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $$
declare
  v_transaction atlas.financial_source_transactions%rowtype;
begin
  select * into v_transaction
  from atlas.financial_source_transactions transaction
  where transaction.id=new.financial_transaction_id;

  if v_transaction.id is null then
    raise exception 'Financial transaction review requires an existing source transaction.' using errcode='23503';
  end if;

  if new.financial_evidence_observation_id is not null then
    if v_transaction.financial_source_account_id is null
       or v_transaction.current_financial_evidence_observation_id is null
       or new.source_observation_id is not null
       or new.financial_evidence_observation_id<>v_transaction.current_financial_evidence_observation_id then
      raise exception 'An account-centered financial transaction review must snapshot the transaction current financial evidence observation only.' using errcode='23514';
    end if;
    return new;
  end if;

  if new.source_observation_id is null
     or v_transaction.current_observation_id is null
     or new.source_observation_id<>v_transaction.current_observation_id then
    raise exception 'A connector-backed financial transaction review must snapshot the transaction current source observation.' using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_financial_source_review_event_v1() is
  'Requires every immutable financial review receipt to snapshot exactly the current evidence version for its connector-backed V1 or account-evidence-backed V2 transaction.';
