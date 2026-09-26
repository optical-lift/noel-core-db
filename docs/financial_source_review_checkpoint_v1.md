# Financial Source Review Checkpoint v1

Status: source-complete for the mixed-source review tranche; not production-promoted.

Purpose: extend the existing Atlas connected-source, Reality/Ledger, commercial, and Package 5 financial authority so a Principal can preserve neutral source transactions before interpretation; reconcile one movement across multiple sources; reconcile a bank credit to commercial payment truth that Atlas already knows; decide nonbusiness versus organization use; and promote only human-confirmed business meaning into governed Spend or Organization Receipt truth.

## Truth boundaries

- A financial source's access carrier is not its owner/custodian.
- Canonical source custody points to a `reality.entities` Person or other entity. A named owner may remain `claimed_unresolved` until that referent is lawfully established in Reality.
- Statement ingestion writes source evidence only. It does not establish business purpose, tax treatment, income, expense, or transfer meaning.
- Source custody does not establish transaction purpose. A personally owned source can fund organization activity; a business-owned source can contain nonbusiness or other-business activity.
- Transfer candidates use structural facts only: remaining amount, currency, different source, and nearby date. Merchant text is not authority.
- Transfer kind is human-confirmed.
- Credit capacity is shared across transfer reconciliation, reconciliation to existing commercial payment truth, and inflow allocation. One dollar cannot occupy more than one of those meanings.
- Reconciliation to an existing commercial payment never creates a second sale or second revenue record.
- An Organization Receipt records cash received for an organization when no existing commercial payment is being reconciled. Receipt kind is not a sales order and is not tax treatment.
- Debit organization allocation promotes into Package 5 Spend only after human confirmation.
- Spend funding kind is derived from Reality source custody, never from the legacy connected-source access carrier. Unresolved source ownership remains unresolved funding.
- Disputed or voided source transactions cannot be reconciled or promoted.
- Bookkeeping reads and business allocations require an active native Ledger seat. Legacy Principal-Ledger authority rows are not used as canonical access authority.
- Native `ledger.ledgers` is canonical Ledger identity. `atlas.organizations` is retained only where current Package 5 compatibility routing still requires it.

## Current app encounter

`Personal Atlas -> Money -> establish source -> import normalized CSV statement -> review unresolved transactions`

From there:

- likely source-to-source movements can be confirmed as a transfer type;
- source credits matching existing Atlas commercial payment truth can be reconciled without duplicating income;
- debit rows can be marked personal / household / nonbusiness or assigned to an authorized Ledger as governed Spend;
- credit rows can be marked personal / household / nonbusiness or assigned to an authorized Ledger as an Organization Receipt with an explicit receipt kind;
- source setup asks who actually owns the source. A source owned by a person/business not yet canonical in Reality may preserve a named unresolved owner rather than falsely assigning ownership to the signed-in user.

The CSV statement importer requires explicit date / description / amount mapping and explicit sign convention. Bank-specific adapters should normalize into this same source-evidence membrane rather than bypass it.

## CPA handoff

The Organization Ledger bookkeeping surface now keeps three lanes visibly separate:

1. canonical commercial income already known from orders/payments;
2. Organization Receipts that represent other or not-yet-reconciled cash receipts;
3. governed Organization Spend and its downstream reporting interpretation.

The CPA CSV does not silently fold Organization Receipts into canonical commercial income and does not guess tax treatment. Unclassified rows remain visibly reviewable.

## Acceptance fixtures

Redacted fixtures preserve the real structural cases that motivated the tranche without committing private financial data:

- checking -> credit-card payment;
- checking -> second account transfer;
- personally accessed source -> differently held source movement, without inferring owner contribution from source labels;
- same-source reversal excluded;
- matching description text cannot override mismatched amount evidence;
- a Receipt-consumed credit has zero transfer/commercial capacity left;
- a commercially reconciled credit has zero transfer/Receipt capacity left;
- partial dispositions expose only the true residual;
- source funding labels derive from canonical Reality custody;
- a claimed unresolved business owner is not replaced by the signed-in access carrier.

## Known identity dependency

The real 2025 bookkeeping evidence identifies an account owner that is not yet a canonical Atlas Reality entity. Atlas must not solve that by calling the account personally owned or by pretending an operating DBA is the legal source owner.

The source may therefore remain `claimed_unresolved` while its statement history is admitted and reviewed. Later binding to a canonical Reality entity preserves the existing source observations and transaction history. Binding a source to a non-self entity requires an explicit `financial_source_custody` responsibility relation with the `financial_source.custody_bind` operation; a Ledger seat or business relationship does not silently grant that authority.

A general Reality entity / entity-relationship promotion membrane is still needed for cases where the referent does not already exist in Reality or Shared Intelligence. That is a universal Reality/Implementation dependency, not a bookkeeping-only exception.

## Release boundary

No migration in this tranche has been promoted to production, no real financial transaction has been written to production, no PR has been opened, and no GitHub Actions run is required while private Actions are unavailable.

Before release:

1. run the migration/schema validation harness against a production-schema clone;
2. run the redacted transfer/inflow/custody fixtures;
3. perform a signed-in human proof with disposable financial sources and statement rows;
4. verify transfer, commercial-reconciliation, Spend, Receipt, and custody-binding capacity boundaries;
5. only then use real bookkeeping data.