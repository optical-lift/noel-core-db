# Initial Personal Atlas $7 collection custody — CANDIDATE ONLY

Founder: a Personal Atlas starts its monthly $7 service obligation at enrollment. First card collection must happen within seven days (possibly sooner if the same payer explicitly agrees to a Ledger or connection seat). No upfront one-time Foundry onboarding price. No free first month and no implicit sponsorship.

Selected billing implementation: Stripe Setup Checkout secures reusable card consent; the same Stripe Customer gets a manual **draft** first-month invoice, editable during a seven-day max window and consisting initially of $7. Same-payer, separately accepted additional lines may be added while draft. Finalize/pay at due or earlier on authorized addition. The recurring subscription runs on the enrollment anniversary, with its first automated invoice deferred only because the first month has been billed explicitly. Stripe must retain independent evidence of both. Provider checkout and invoice creation require complete idempotent service orchestration, not mere JS timers.

This candidate table carries session/customer/subscription/invoice identifiers, service start, first-month period, due deadline, amount and status. Only service role can mutate it. Untrusted Auth users have no direct table or RPC grants. Claim operation is concurrency-bounded with SKIP LOCKED and a renewable lease, but **does not itself pay any invoice**. The collecting service must retrieve actual current Stripe status and use provider idempotency before finalizing/paying, then record verified result. Never treat a provider event body as current state without verification.

**Source review blockers:**
- The candidate has not been parsed or tested in a disposable DB clone and is not a generated release migration.
- No real Stripe Setup Checkout integration, subscription creation, drafted invoice item writer, scheduled collection job, verified payer-adding-Ledger mutation, dunning, or access hard-lock exists yet.
- Verify invoice due semantics, card consent/off-session behavior, billing-cycle origin, SCA failures, duplicate webhooks, 15-minute lease recovery, and multi-tenant payer isolation.
- Existing `personal_atlas_access_status_self_api_v1` must be reconciled to hard-lock after delinquent initial invoice even if Stripe subscription still reports trialing. Do not infer access from metadata or UI state.
- Existing Stripe `trial_end` one month in Atlas PR #243 is the old incorrect signup path and must not be released until this provider/invoice flow replaces it.
- No production DDL, Stripe charges, or existing billing changes made.

This candidate is an enabling schema only. Program invitations and 15K drafts remain independent and parked until specific program facts exist.
## Immutable first-verified-setup stage

The candidate now starts with a service-only, verified-SetupIntent registration before it ever creates an invoice. The first write freezes the DB service-start timestamp and fixed due time (6 days, leaving time for an daily UTC collector to satisfy the seven-day outer bound). Retried webhook/browser confirmations reuse those exact timestamps. A second writer only moves `preparing` to `draft` after it independently verifies the Stripe subscription, draft invoice and first $7 invoice item. This avoids an early server error minting a second subscription or first invoice during a retry. The production migration, Stripe orchestration and collection job remain not released.

## Initial-invoice delinquency is an access fact

The service-only reconciler combines freshly retrieved Stripe subscription status with the first-invoice custody state. A failed first invoice maps Personal Atlas purchase state to `past_due` even while Stripe says the separately billed renewal subscription is trialing. A later subscription webhook must invoke the reconciler after its existing v2 writer, or it could reactivate the user without the first $7 ever being collected. A paid recovery may restore access only when the current subscription is also active/trialing. This candidate is not deployed.

**Vercel Hobby constraint:** Production Vercel will not accept an hourly cron. Invoice collection becomes eligible six days after signup; the next daily UTC run is targeted to collect before day seven, provided the scheduler is operating. Always retain the seven-day maximum as the disclosed upper bound and issue explicit failure/recovery handling when collection is delayed by outages.
