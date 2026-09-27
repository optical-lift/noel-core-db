-- Redacted acceptance fixture for Atlas financial-source transfer suggestions v1.
--
-- Purpose:
--   Preserve the real structural cases that motivated this tranche without
--   committing private statement content, account numbers, merchants, or amounts.
--
-- This validates suggestion logic only. It does NOT validate or infer transfer
-- meaning. Human confirmation remains authoritative for internal_transfer,
-- liability_payment, owner_contribution, owner_draw, reimbursement, or other.

begin;

do $fixture$
declare
  v_candidate_count integer;
  v_wrong_source_count integer;
  v_text_authority_count integer;
begin
  with transactions(id, source_id, transaction_date, direction, amount, currency, description) as (
    values
      -- Checking -> credit-card payment: same amount, opposite direction,
      -- different sources, one day apart.
      ('checking-card-debit','checking',date '2025-01-10','debit',101.00::numeric,'USD','REDACTED PAYMENT'),
      ('checking-card-credit','credit-card',date '2025-01-11','credit',101.00::numeric,'USD','REDACTED RECEIPT'),

      -- Checking -> second account movement: same amount, same day.
      ('checking-joint-debit','checking',date '2025-01-17','debit',202.00::numeric,'USD','REDACTED TRANSFER'),
      ('checking-joint-credit','joint-account',date '2025-01-17','credit',202.00::numeric,'USD','REDACTED DEPOSIT'),

      -- Personally held source -> organization-held source. Structural evidence
      -- may suggest the movement, but must not decide that it is an owner
      -- contribution merely because the destination is organizational.
      ('personal-org-debit','personal-source',date '2025-01-24','debit',303.00::numeric,'USD','UNHELPFUL TEXT A'),
      ('personal-org-credit','organization-source',date '2025-01-25','credit',303.00::numeric,'USD','UNHELPFUL TEXT B'),

      -- Same-source opposite entries must never be suggested as a cross-source
      -- transfer pair by this membrane.
      ('same-source-debit','checking',date '2025-01-28','debit',404.00::numeric,'USD','REVERSAL'),
      ('same-source-credit','checking',date '2025-01-28','credit',404.00::numeric,'USD','REVERSAL'),

      -- Matching text with different amounts must not manufacture a candidate.
      ('text-only-debit','checking',date '2025-01-30','debit',505.00::numeric,'USD','MAGIC TRANSFER LABEL'),
      ('text-only-credit','savings',date '2025-01-30','credit',506.00::numeric,'USD','MAGIC TRANSFER LABEL')
  ), candidates as (
    select
      d.id as from_id,
      c.id as to_id,
      d.amount,
      d.currency,
      abs(d.transaction_date-c.transaction_date) as day_distance
    from transactions d
    join transactions c
      on d.direction='debit'
     and c.direction='credit'
     and c.currency=d.currency
     and c.amount=d.amount
     and c.source_id<>d.source_id
     and abs(d.transaction_date-c.transaction_date)<=3
  )
  select count(*) into v_candidate_count from candidates;

  if v_candidate_count <> 3 then
    raise exception 'Expected exactly 3 structural transfer candidates, found %.', v_candidate_count;
  end if;

  with transactions(id, source_id, transaction_date, direction, amount, currency, description) as (
    values
      ('same-source-debit','checking',date '2025-01-28','debit',404.00::numeric,'USD','REVERSAL'),
      ('same-source-credit','checking',date '2025-01-28','credit',404.00::numeric,'USD','REVERSAL')
  )
  select count(*) into v_wrong_source_count
  from transactions d
  join transactions c
    on d.direction='debit'
   and c.direction='credit'
   and c.amount=d.amount
   and c.currency=d.currency
   and c.source_id<>d.source_id;

  if v_wrong_source_count <> 0 then
    raise exception 'Same-source entries must not become transfer candidates.';
  end if;

  with transactions(id, source_id, transaction_date, direction, amount, currency, description) as (
    values
      ('text-only-debit','checking',date '2025-01-30','debit',505.00::numeric,'USD','MAGIC TRANSFER LABEL'),
      ('text-only-credit','savings',date '2025-01-30','credit',506.00::numeric,'USD','MAGIC TRANSFER LABEL')
  )
  select count(*) into v_text_authority_count
  from transactions d
  join transactions c
    on d.direction='debit'
   and c.direction='credit'
   and c.currency=d.currency
   and c.amount=d.amount
   and c.source_id<>d.source_id
   and abs(d.transaction_date-c.transaction_date)<=3;

  if v_text_authority_count <> 0 then
    raise exception 'Merchant/description text must not override structural amount evidence.';
  end if;
end
$fixture$;

rollback;
