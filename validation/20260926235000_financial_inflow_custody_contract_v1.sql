-- Redacted contract fixture for financial inflow capacity and source custody.
-- No real statement amounts, account identifiers, entity IDs, or merchant text.

begin;

do $fixture$
declare
  v_remaining numeric;
  v_candidate_count integer;
  v_funding_kind text;
  v_owner text;
begin
  -- A credit consumed as an Organization Receipt has no capacity left to become
  -- a transfer candidate or commercial reconciliation.
  with credit(amount) as (values (100::numeric)),
       transfers(amount) as (values (0::numeric)),
       receipts(amount) as (values (100::numeric)),
       commercial(amount) as (values (0::numeric))
  select c.amount-t.amount-r.amount-m.amount
  into v_remaining
  from credit c cross join transfers t cross join receipts r cross join commercial m;
  if v_remaining<>0 then raise exception 'Receipt-consumed credit must have zero remaining capacity.'; end if;

  -- A credit reconciled to existing commercial truth likewise has no remaining
  -- capacity for a second receipt or transfer.
  with credit(amount) as (values (200::numeric)),
       transfers(amount) as (values (0::numeric)),
       receipts(amount) as (values (0::numeric)),
       commercial(amount) as (values (200::numeric))
  select c.amount-t.amount-r.amount-m.amount
  into v_remaining
  from credit c cross join transfers t cross join receipts r cross join commercial m;
  if v_remaining<>0 then raise exception 'Commercially reconciled credit must have zero remaining capacity.'; end if;

  -- Partial meaning leaves only the actual residual available.
  with credit(amount) as (values (300::numeric)),
       transfers(amount) as (values (100::numeric)),
       receipts(amount) as (values (75::numeric)),
       commercial(amount) as (values (25::numeric))
  select c.amount-t.amount-r.amount-m.amount
  into v_remaining
  from credit c cross join transfers t cross join receipts r cross join commercial m;
  if v_remaining<>100 then raise exception 'Credit residual must subtract transfer, receipt, and commercial reconciliation capacity exactly once.'; end if;

  -- Candidate matching uses remaining capacity, so a fully consumed credit is
  -- structurally ineligible even when an opposite debit has the original amount.
  with debits(id,remaining_amount,currency) as (
    values ('debit-a',400::numeric,'USD')
  ), credits(id,remaining_amount,currency) as (
    values ('credit-consumed',0::numeric,'USD')
  ), candidates as (
    select d.id,c.id from debits d join credits c
      on c.remaining_amount=d.remaining_amount
     and c.remaining_amount>0
     and c.currency=d.currency
  )
  select count(*) into v_candidate_count from candidates;
  if v_candidate_count<>0 then raise exception 'Consumed credit must not reappear as transfer candidate.'; end if;

  -- Funding kind comes from canonical custody, never from who happened to enter
  -- or sync the source.
  with cases(custody_state,custodian_kind,same_as_target,same_as_person,expected) as (
    values
      ('canonical','business',true,false,'organization'),
      ('canonical','person',false,true,'organization_member'),
      ('canonical','business',false,false,'external_party'),
      ('claimed_unresolved','unknown',false,false,'unresolved'),
      ('legacy_unresolved','unknown',false,false,'unresolved')
  )
  select string_agg(
    case
      when (case
        when custody_state='canonical' and same_as_target then 'organization'
        when custody_state='canonical' and same_as_person then 'organization_member'
        when custody_state in ('claimed_unresolved','legacy_unresolved') then 'unresolved'
        else 'external_party'
      end)=expected then null else expected end,
    ','
  ) into v_funding_kind
  from cases;
  if v_funding_kind is not null then raise exception 'Reality-custody funding derivation failed.'; end if;

  -- A claimed unresolved business owner remains that claim. The signed-in access
  -- carrier must not replace it with the carrier person's identity.
  with source(access_carrier,custody_state,claimed_owner,custodian_entity) as (
    values ('signed-in-person','claimed_unresolved','Example Legal Business LLC',null::text)
  )
  select case
    when custody_state='claimed_unresolved' and custodian_entity is null then claimed_owner
    else access_carrier
  end into v_owner
  from source;
  if v_owner<>'Example Legal Business LLC' then raise exception 'Unresolved source owner claim was overwritten by access carrier.'; end if;
end
$fixture$;

rollback;