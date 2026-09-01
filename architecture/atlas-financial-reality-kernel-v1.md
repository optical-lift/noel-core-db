# Atlas Financial Reality Kernel v1

## Purpose

Atlas must understand a business's financial reality without turning any one provider into the accounting truth.

Stripe, a bank, QuickBooks, an invoice, a receipt, a customer record, a vendor record, and an Atlas domain transaction may all describe different parts of the same economic event. The kernel must preserve those statements independently, reconcile them when evidence warrants it, and surface unresolved contradictions as operational work.

The governing chain is:

```text
connected source
  -> immutable source observation
  -> canonical economic event
  -> accepted evidence links / event relations
  -> classification + reconciliation position
  -> unresolved financial consequence
  -> Company Work admission
```

This is not a replacement for QuickBooks. QuickBooks may remain the accounting ledger. Atlas needs enough financial truth to understand what happened, what is still uncertain, what has operational consequences, and what should be handed back to accounting/tax systems.

## Relationship to Money Collection

The existing Money Collection design remains valid but narrower.

Money Collection answers:

1. why money is owed;
2. how much remains owed;
3. what money was received or reversed;
4. which obligation the receipt satisfied.

Financial Reality sits above and beside that subsystem.

A `money_receipt` can establish or corroborate a canonical financial event, but not every financial event is a receivable or receipt. Expenses, processor fees, bank transfers, payouts, vendor payments, taxes, interest, owner contributions, refunds, and accounting classifications all exist outside a simple collection model.

Therefore:

```text
Financial Reality
  contains/reconciles -> Money Collection evidence
  does not replace    -> Money Collection obligation authority
```

## Source authority

`atlas.connected_sources` remains the external-account root.

A source can be Stripe, a bank-feed provider, QuickBooks, another accounting system, a receipt/document source, or a future financial provider. Provider credentials remain outside `connected_sources`; only non-secret source identity, custody, capabilities, authorization state, and synchronization state belong there.

A provider owns only what it observed.

Examples:

- Stripe can truthfully say a balance transaction had gross, fee, net, source object, availability state, and payout linkage.
- A bank can truthfully say a deposit or withdrawal posted to an account.
- QuickBooks can truthfully say an invoice/customer/account/category mapping exists in its ledger.
- An Atlas Sale can truthfully say the business committed a sale at an authoritative amount.

None of those statements automatically proves the others.

## Core object 1 — Financial Source Observation

A Financial Source Observation is immutable evidence imported from one connected source.

Minimum identity:

```text
organization_id
connected_source_id
provider_record_kind
provider_record_id
observation_fingerprint
```

The same provider object may be observed more than once as its provider-owned state changes. Atlas therefore stores append-only snapshots rather than mutating an old observation into a new fact.

Minimum normalized fields should support:

- provider record kind and id;
- provider parent/source ids where available;
- observed timestamp;
- provider effective/posted timestamp;
- gross amount;
- fee amount;
- net amount;
- currency;
- direction when the provider establishes it;
- counterparty/customer/vendor hints;
- invoice/document/reference number;
- description/memo;
- provider state;
- provider-owned category/account hints;
- normalized provider data;
- payload hash/fingerprint;
- source-event id when delivered through an event/webhook;
- raw payload custody reference when raw payload storage lives elsewhere.

An observation is evidence, not an economic event.

## Core object 2 — Canonical Economic Event

A Canonical Economic Event is Atlas's provider-neutral identity for one economic occurrence.

Examples include:

- revenue;
- expense;
- customer payment;
- vendor payment;
- processor fee;
- refund;
- payout;
- transfer;
- tax movement;
- interest;
- receivable/payable settlement;
- owner contribution/distribution;
- other business-specific economic movement.

The event kind is intentionally extensible. Atlas must not require a schema migration each time a legitimate business introduces a new economic shape.

Minimum event truth:

- organization custody;
- stable event key;
- event kind;
- cash direction: `inflow`, `outflow`, `transfer`, or `noncash`;
- non-negative amount plus separate direction;
- currency;
- occurred/effective timestamp;
- optional counterparty snapshot;
- optional internal source-domain identity;
- authority kind and authority reference;
- metadata explaining the admission basis.

An event may be admitted because an internal Atlas domain has canonical authority, because an external financial source establishes a bank/processor movement, or because an authorized human resolves ambiguous evidence.

A model suggestion alone does not establish canonical financial truth.

## Core object 3 — Evidence Link

Many source observations can describe one event, and one source observation can legitimately participate in more than one event.

Examples:

```text
Stripe charge observation
  -> customer_payment event

Stripe balance transaction observation
  -> customer_payment event
  -> processor_fee event

Stripe payout observation
  -> payout event

bank deposit observation
  -> payout event

QuickBooks invoice observation
  -> receivable/revenue event

receipt image observation
  -> expense event
```

The evidence link records the role of the observation:

- `establishes` — sufficient under a registered adapter contract to establish this event;
- `corroborates` — supports an already-established event;
- `documents` — provides documentary evidence;
- `classifies` — contributes accounting/category evidence;
- `settles` — proves settlement-side evidence;
- `contradicts` — preserves a material conflict instead of silently choosing one source.

Accepted evidence links are durable provenance. Rejected match candidates must not be rewritten into accepted history.

## Core object 4 — Economic Event Relation

Financial truth often consists of relationships between real events rather than one flattened transaction row.

Examples:

```text
processor_fee --fee_on--> customer_payment
refund --refund_of--> customer_payment
payout --contains--> customer_payment net settlement
bank_deposit --settles--> payout
customer_payment --settles--> receivable
vendor_payment --settles--> payable
transfer_out --counterpart_of--> transfer_in
```

This prevents false revenue duplication.

A Stripe payment, a Stripe payout, and the bank deposit receiving that payout must not become three sales merely because all three involve positive money values at different layers.

## Classification authority

Classification is separate from event existence.

A real expense can be known before Atlas knows whether it belongs to `Repairs`, `Supplies`, `Advertising`, or another bookkeeping/tax category.

Classification evidence must therefore be append-only and provenance-bearing.

Classification sources may include:

- QuickBooks/accounting-system account or category;
- explicit human classification;
- organization-specific deterministic rule;
- provider category hint;
- model suggestion.

Precedence is not universal. A provider hint or model suggestion must never silently overwrite a human/accounting-system classification. Conflicts remain visible until resolved or a governing organization policy explicitly decides precedence.

Atlas should preserve at least:

- taxonomy/system key;
- classification key;
- display label snapshot;
- source kind/source id;
- authority level;
- confidence when inferential;
- effective timestamp;
- supersession/rejection evidence.

## Reconciliation

Reconciliation is the process of establishing that multiple observations/events belong to the same economic chain.

It is not string matching, amount matching, or provider preference.

Candidate generation may use:

- amount/net amount;
- currency;
- time window;
- invoice number;
- customer/vendor identity;
- provider source ids;
- payout ids;
- bank trace/reference ids;
- memo/description;
- known settlement windows;
- explicit internal source lineage.

Candidate generation has no truth authority.

An accepted reconciliation must preserve:

- exact objects being related;
- relation kind;
- admission basis;
- confidence if inferential;
- whether a human/system rule accepted it;
- source references;
- timestamp;
- any contradiction that remains unresolved.

## Stripe adapter proof

Stripe is the first external adapter because it demonstrates multiple financial layers inside one provider.

The adapter should ingest at least:

- invoices and invoice/payment relationships where available;
- customers/counterparty hints needed for reconciliation;
- charges/payment intents as payment evidence;
- balance transactions as gross/fee/net movement evidence;
- refunds;
- disputes/reversals where applicable;
- payouts and payout settlement identifiers.

Stripe Balance Transactions are especially important because Stripe represents gross amount, fee, net impact, source object, and availability state separately. The adapter should preserve that decomposition instead of flattening a processor fee into lower revenue.

Stripe OAuth for Atlas is a source-authorization concern, not Financial Reality authority. The connected source must be organization-owned when it represents organizational books. Reusable OAuth credentials remain outside `atlas.connected_sources`.

## Bank adapter contract

A future bank adapter should require no Financial Reality schema change.

It should write the same Financial Source Observation contract for:

- posted deposits;
- withdrawals;
- ACH/card/check movements;
- fees;
- interest;
- transfers;
- stable bank references/trace ids when available.

A bank deposit that matches a Stripe payout corroborates settlement. It does not create a new revenue event.

## QuickBooks/accounting adapter contract

A future QuickBooks adapter should also require no Financial Reality schema change.

It can contribute evidence for:

- invoice/document numbers;
- customer/vendor identity;
- receivable/payable state;
- chart-of-accounts/category classification;
- payment application;
- journal/accounting references.

QuickBooks classification is accounting evidence. Atlas may use it when exporting or operating the business, but importing QuickBooks must not erase contradictory bank/processor evidence.

## Tax/export contract

A tax/bookkeeping export is a projection of reconciled Financial Reality, not a provider dump.

For each exported economic event, Atlas should be able to provide as applicable:

- canonical event id;
- date/effective date;
- gross amount;
- fees;
- net amount;
- currency;
- customer/vendor/counterparty;
- invoice/document/reference number;
- effective bookkeeping/category classification;
- bank transaction reference;
- processor transaction reference;
- accounting-system reference;
- reconciliation state;
- evidence/source ids;
- unresolved warnings.

The export must distinguish:

- fully reconciled;
- partially reconciled;
- classification missing;
- contradictory evidence;
- source coverage incomplete.

Atlas must not make a tax-completeness claim when source coverage or reconciliation is incomplete.

## Operational consequence / Company Work

Financial truth becomes operational only through an explicit consequence adapter.

Examples:

```text
invoice due + no admissible payment evidence
  -> receivable follow-up candidate

processor payout expected + no bank settlement evidence after expected window
  -> settlement investigation candidate

posted business expense + no document/category after organization grace period
  -> expense reconciliation candidate

provider/accounting contradiction
  -> bookkeeping review candidate

period close + unresolved reconciliation cases
  -> closeout work candidate
```

The Financial Reality kernel itself does not arbitrarily create tomorrow's tasks.

Instead it produces source-backed reconciliation gaps with explicit consequence/window evidence. The existing Company Work authority decides whether that unresolved financial consequence is an organizational obligation and who is responsible. Worker Day/Clock then decides when it appears.

This preserves:

```text
financial fact != task
reconciliation gap != Principal work
Company Work admission != Clock placement
```

## Provider-neutral launch invariant

After v1, adding a bank provider or accounting provider must not require:

- adding provider-specific columns to canonical economic events;
- adding provider-specific customer/vendor columns;
- creating a second transaction table;
- changing Money Collection obligation semantics;
- changing Company Work semantics.

A new adapter should only need to:

1. authorize a connected source;
2. normalize provider records into Financial Source Observations;
3. register the adapter's evidence/admission contracts;
4. optionally add deterministic reconciliation rules specific to that provider's stable identifiers.

## No destructive heuristics

The following are prohibited as automatic canonical truth:

```text
same amount + nearby date -> same transaction
Stripe payout -> revenue
bank deposit -> revenue
fulfilled sale -> paid
invoice marked paid in one provider -> bank settled
provider category -> tax category
model confidence -> accepted classification
missing source record -> did not happen
```

Those may generate candidates. They cannot silently become accepted truth.

## First executable proof

The first executable kernel tranche should prove:

1. organization-owned `connected_sources` remain the external source root;
2. source observations are append-only and idempotent by provider identity + fingerprint;
3. observations cannot cross organization custody;
4. economic events are provider-neutral and stable-key idempotent;
5. one observation can evidence multiple events without duplicating the source record;
6. multiple observations can evidence one event;
7. event relations prevent payout/deposit layers from being treated as duplicate revenue;
8. classification evidence remains separate from event existence;
9. unresolved/contradictory reconciliation remains visible rather than guessed away;
10. Money Collection receipts/obligations can be attached as internal evidence without becoming the whole financial model;
11. Stripe can later attach through this contract without schema changes;
12. bank and QuickBooks adapters can attach through the same contract without schema changes.

## Governing principle

**Providers report. Atlas reconciles. Domains establish what they own. Accounting systems classify what they own. Financial Reality preserves the chain and the uncertainty. Operational authority decides what the business must do next.**
