# Foundry-assessed onboarding price custody — draft

**2026-10-12 founder ruling:** The $7 Personal Atlas subscription and $7 Ledger-connected employee-seat are distinct monthly components. Employer sponsorship of both is $14/month, not a contradictory $7 or $14 seat rate. No new bundled entitlement should be created.

A Personal Atlas previously had a $39.95 signup setup charge; a first Ledger implementation previously had a $3,000 charge with up-front or three-installment selection. **Neither one-time onboarding price is to be charged, quoted as fixed, or treated as contracted during signup.** Foundry evaluates real circumstances and only after discovery does the person/organization review and explicitly accept a proposed onboarding amount and scope. This candidate **does not implement** that later Foundry quoting/acceptance writer; that must be a separate governed economic fact.

## Existing live schema collision
- `atlas.implementation_purchases.setup_contract_amount_cents` and `atlas.ledger_entitlements.setup_price_cents` currently `NOT NULL`; setting either to zero would falsely record a zero-dollar agreement rather than unknown.
- `atlas.record_stripe_implementation_purchase_v1` accepts `pay_in_full | three_installments`; current checkout/webhook assumes an upfront paid setup line.
- `atlas.personal_atlas_purchase_state_from_stripe_status_internal_v1` already correctly maps **trialing** to active.
- `record_stripe_personal_atlas_purchase_v2` can store a trialing subscription; no personal database migration is necessary to remove a setup line item.
- Draft Atlas PR #243 changes Personal checkout to recurring price only and Ledger checkout to recurring Ledger only. Stripe Checkout with no upfront amount may be `payment_status=no_payment_required`; still require fresh active/trialing provider subscription and signed checkout provenance before entitlement.

## Candidate SQL
- Preserve all historical paid rows and the existing v1 RPC.
- Allow **NULL unknown** one-time setup amount, not 0, and `foundry_assessed` on implementation purchase.
- Add a new **service-only** v2 implementation checkout custody RPC, rejecting any setup price supplied and requiring the explicit Foundry-pending signup state.
- Keep the recurring Ledger subscription and baseline unbound Ledger entitlement separate from the later one-time onboarding proposal. Billing/scope reconciliation must never backfill a Foundry quote into historical Stripe Checkout evidence.

## Missing proof / release holds
1. Disposable PostgreSQL clone parse and replay; verify no global regression to pre-existing v1 paid data/checkout.
2. Service-only v2 grant; deny anonymous and authenticated. Validate idempotent repeat, setup amount sent accidentally, under-specified state, and wrong-session/provider claims.
3. Provider test-mode Checkout with no setup line, `no_payment_required`+trialing and actual first invoice; webhook/browser return race/replay.
4. Governed Foundry assessment proposal, human acceptance, later specific charge and allocation to acquired Ledger scope; do not invent an amount today.
5. Organization subscription lifecycle after first paid month, cancellation/lock and recovery. Personal subscription custody exists separately and must not be blindly copied.
6. Source-first canonical migration workflow after review and explicit authorization; no direct SQL on live `noel-core`.

**No live SQL was executed.** This is candidate source only.
