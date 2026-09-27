# Atlas Financial Evidence Resolution v1

## Status

Source candidate on `work/atlas-financial-obligation-settlement-v1`.

This tranche is intentionally source-only until private Database Custody CI is available again. Do not interpret the existence of this migration as production release proof.

## Problem

A financial account row is not yet economic meaning.

The same real event can leave several independent witnesses:

- commerce or donation system record;
- processor event;
- email or receipt;
- bank/card transaction;
- a transfer between two financial sources;
- later accounting interpretation.

If Atlas treats each witness as the event, it double-counts reality. If it immediately calls the bank row revenue, expense, owner funding, debt repayment, or a journal entry, it skips unresolved economic truth.

The required boundary is:

```text
raw/provider evidence
        ↓
financial source transaction
        ↓
optional source movement reconciliation
        ↓
FINANCIAL EVIDENCE RESOLUTION
        ↓
economic obligation / settlement (when warranted)
        ↓
accounting interpretation
        ↓
journal posting
```

The resolution layer answers one operator question:

> What was this actually for?

It does not answer how an accountant should post it.

## Core rule

**Many witnesses may resolve to one economic event.**

The migration therefore keeps three concepts separate.

### 1. Economic event

`atlas.financial_economic_events`

One row is one operator-confirmed Reality Sentence about the economic meaning of money evidence. It records:

- stable operator event key;
- local/observed date and optional exact instant;
- positive event amount and currency;
- required `meaning_statement`;
- governed creator Principal/user;
- exact request fingerprint for replay safety;
- confirmed/voided lifecycle with retained correction history.

The meaning statement is deliberately not a chart-of-accounts taxonomy. Examples of valid meaning are conceptually:

- a purchase made for a business activity;
- a contribution from one Person to a Business;
- a customer payment for a specific activity;
- a transfer between two stores of the same money.

Whether any of those later become revenue, expense, equity, receivable settlement, loan activity, or another accounting treatment remains downstream.

### 2. Monetary source allocation

`atlas.financial_economic_event_source_allocations`

This is the only child relation that consumes money capacity.

An event can allocate against:

- an unreconciled residual of `atlas.financial_source_transactions`; or
- a confirmed `atlas.financial_source_movement_matches` movement.

All allocations for one event must equal the event amount exactly.

A source transaction already included in a confirmed movement match cannot have that matched capacity allocated directly again. Only the unmatched residual remains available for direct economic attribution.

That gives Atlas this invariant:

```text
source transaction magnitude
  >= confirmed movement-matched amount
   + confirmed direct economic-event allocation
```

And independently:

```text
movement amount
  >= confirmed economic-event allocations through that movement
```

This is the structural double-counting barrier.

### 3. Witness link

`atlas.financial_economic_event_evidence_links`

Witness links consume **zero** monetary capacity. They can point to:

- `atlas.evidence_records`;
- a financial source transaction; or
- a source movement match.

A witness can be marked:

- `supports`;
- `contradicts`; or
- `context`.

This is what allows GiveWP, Stripe, an email, and the bank to all describe one economic event without four events appearing in financial reality.

Contradictory evidence is retained explicitly. It is never silently merged into the preferred interpretation.

## Parties and context

`atlas.financial_economic_event_parties` binds canonical `reality.entities` to event-specific roles such as payer, payee, donor, recipient, owner, beneficiary, processor, customer, vendor, borrower, or lender.

A role is not a permanent property of the entity. The same Person or Business can occupy different capacities in different events.

`atlas.financial_economic_event_dimensions` provides structured context such as business context, property, activity, project, location, contract, or fund.

Canonical Reality entities are used when that identity already exists. For domains not yet promoted into `reality.entities`, an existing `(subject_domain, subject_kind, subject_id)` identity may be retained. V1 does not invent parallel Property or Activity identity systems simply to make the financial layer work.

## Reality Sentence membrane

The first governed self command is:

`atlas.establish_financial_economic_event_self_api_v1(...)`

Conceptually, the Implementation Workbench can compile a human sentence such as:

```text
This $300 movement was a contribution from Person A to Business B.
```

into:

- one economic event;
- the exact monetary source allocation;
- Person A / Business B party roles;
- optional business/property/activity dimensions;
- zero or more supporting/contradicting/context witnesses.

The operator confirms the compiled statement before the service writes it.

The service does not create an obligation, settlement, accounting classification, or journal entry.

## Replay and concurrency

Event identity is `(created_by_principal_id, event_key)`.

The service hashes the complete immutable request. An exact retry returns the existing event. Reusing the key with different meaning/evidence fails.

Creation serializes on:

- Principal + stable event key;
- each source transaction row used as monetary capacity; or
- the movement match used as monetary capacity.

This makes concurrent partial allocations unable to consume the same remaining amount twice.

## Corrections

Economic events are retained history.

Confirmed core meaning is immutable. To correct a wrong economic event:

1. void the old event through `atlas.void_financial_economic_event_self_api_v1(...)`;
2. establish a new event under a new stable key.

Voiding releases that event's monetary capacity for a corrected event while retaining the original event, allocations, witnesses, parties, dimensions, actor, and reason.

Source transactions and movement matches cannot be voided or refreshed into a state that would invalidate still-confirmed economic-event allocations.

## Later evidence

`atlas.link_financial_economic_event_evidence_self_api_v1(...)` can append a new supporting, contradictory, or contextual witness after the original event was confirmed.

Witness rows are append-only. Adding later evidence does not rewrite the original Reality Sentence and does not consume additional money.

## Custody and authorization

All new tables have RLS enabled and direct `public`, `anon`, and `authenticated` table privileges revoked.

Authenticated self APIs require current source authority:

- direct source transaction -> existing connected-source authorization;
- movement match -> authority over every participating connected source;
- `evidence_records` -> compatible Principal, Ledger, or Organization evidence scope.

Canonical party/entity targets must be `reality.entities.identity_state='canonical'`.

## GiveWP → Stripe → email → bank proof path

The first integration proof should deliberately use several witnesses for one event.

For a donation/payment example:

1. GiveWP record becomes or points to governed Evidence.
2. Stripe event becomes Evidence and, when represented as a financial source transaction, may provide the economic monetary anchor.
3. Confirmation email becomes another Evidence record.
4. Stripe payout → bank deposit is reconciled separately as source movement/custody truth.
5. The payout/bank movement may be linked as contextual evidence to the economic event when appropriate, but its existence does not create a second donation/payment event.
6. Processor fees, gross-to-net payout bundling, obligations, settlement, and accounting remain separate downstream facts.

The same architecture can later accept PayPal, WooCommerce, payroll, marketplaces, card accounts, private loans, owner contributions, property expenses, and ordinary bank transactions without adding provider-specific truth tables.

## V1 non-goals

This tranche does **not**:

- classify bank accounts wholesale as personal or business economic meaning;
- infer revenue/expense from sign or account ownership;
- merge or delete raw source rows;
- replace movement reconciliation;
- create obligations or settlements automatically;
- choose a GL account, tax category, or report category;
- post a journal entry;
- turn every contextual witness into another monetary occurrence;
- invent new Person, Business, Property, or Activity identities.

## Static proof checklist before release

The migration is ready for protected clone/CI proof only after confirming:

1. all tables are RLS-enabled and direct browser table access is revoked;
2. exact event retry is idempotent;
3. stable-key conflict with different meaning fails;
4. two concurrent direct allocations cannot exceed source residual;
5. confirmed movement-matched source capacity cannot also be directly allocated;
6. movement allocation cannot exceed movement amount;
7. witness links never consume amount;
8. contradictory evidence remains queryable;
9. canonical Reality party enforcement works;
10. void retains history and releases capacity;
11. provider refresh cannot shrink below confirmed movement + economic allocation;
12. movement cannot be voided while a confirmed economic event consumes it;
13. no obligation, settlement, accounting-posting, or journal-write path is invoked.

Private Actions availability is an operational release gate, not a reason to weaken these contracts.
