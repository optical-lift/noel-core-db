-- Financial review must point at the canonical native Ledger, not declare the
-- Package 5 atlas.ledgers compatibility carrier to be the durable identity.
-- Package 5 still consumes the preserved UUID and legacy Organization routing
-- coordinate during Spend promotion; those are compatibility concerns only.

alter table atlas.financial_transaction_allocations
  drop constraint financial_transaction_allocations_target_ledger_id_fkey;

alter table atlas.financial_transaction_allocations
  add constraint financial_transaction_allocations_target_ledger_id_fkey
  foreign key (target_ledger_id)
  references ledger.ledgers(id)
  on delete restrict;

comment on column atlas.financial_transaction_allocations.target_ledger_id is
  'Canonical native ledger.ledgers identity for the operational beneficiary of a confirmed organization-spend allocation.';

comment on column atlas.financial_transaction_allocations.target_organization_id is
  'Package 5 compatibility routing coordinate required by the current Organization Spend membrane; not the canonical business identity.';
