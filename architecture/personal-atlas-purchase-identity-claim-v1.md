# Personal Atlas Purchase Identity Claim v1

**Status:** source-only candidate; not released  
**Date:** 2026-09-22  
**Purpose:** separate Stripe payer/contact identity from Atlas human identity without weakening purchase custody.

## Problem

The current Personal Atlas acquisition path records Stripe's purchaser email and then requires the authenticated Atlas user's email to match it before the purchase can establish Personal Atlas access.

That collapses two different roles:

```text
payer / billing contact
≠
authenticated Atlas human
```

A spouse, employer, parent, treasurer, assistant, or other authorized payer may buy Atlas for a different human.

The Stripe email remains purchase evidence. It must not become authentication identity merely because it appears first.

## Governing solution

After a Stripe Checkout Session is verified and the Personal Atlas purchase is durably recorded, the server may issue a short-lived one-use **Purchase Claim Ticket**.

```text
verified Stripe purchase
→ service-only claim ticket
→ purchaser chooses Atlas login email
→ Atlas human authenticates
→ server verifies that human
→ service consumes ticket for that auth user
→ purchase.claimed_by_user_id = authenticated human
→ Personal Atlas establishment proceeds
```

The ticket is a narrow bearer capability for **claiming this already-paid Personal Atlas purchase**. It is not payment authority and does not identify the payer as the Atlas human.

## Ticket custody

Raw claim tokens are never stored.

The database stores only SHA-256 of the random token.

A ticket is:

- bound to exactly one `personal_atlas_purchase`;
- short-lived;
- single-use;
- service-issued;
- service-consumed after the application has independently authenticated the target Atlas human;
- not executable by `anon` or `authenticated` roles directly.

States:

`issued → consumed`

with `expired` and `revoked` available for abandoned or superseded tickets.

Issuing a new live ticket revokes an older unconsumed ticket for the same purchase.

## Backward compatibility

Legacy same-email purchases continue to work while the transition is incomplete.

Personal Atlas establishment resolves a purchase by:

1. `claimed_by_user_id = auth.uid()`; otherwise
2. an unclaimed active purchase whose purchaser email matches the auth email.

The claim-ticket path therefore adds the correct identity seam without invalidating existing purchases.

## Non-authority

A claim ticket does not:

- create a Principal;
- create a Household;
- change Stripe billing identity;
- change payer evidence;
- establish an institution;
- create a Ledger;
- create a Commercial Composition;
- authorize any later commercial charge.

It only binds an already-recorded paid Personal Atlas purchase to the authenticated human who will use it.

## Application transport

The browser should not receive or nominate `claimed_by_user_id`.

Recommended transport:

1. Checkout verification issues the claim token server-side.
2. The application stores it in a short-lived HTTP-only SameSite cookie.
3. The human supplies the email they want to use for Atlas and authenticates it.
4. A server claim endpoint verifies the Supabase bearer token and consumes the cookie ticket for that verified user id.
5. The claim cookie is cleared.
6. Atlas opens through the normal Personal setup journey.

This keeps the claim token out of ordinary UI state and prevents the browser from asserting another human id.
