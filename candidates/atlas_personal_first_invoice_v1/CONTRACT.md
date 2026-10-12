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