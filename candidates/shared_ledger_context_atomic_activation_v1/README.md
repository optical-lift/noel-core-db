# Shared Ledger context — atomic identity at governed Ledger activation v1

**Status:** source-only candidate; not deployed or merged.  
**Release lane:** `shared_` (Ledger/Reality cross-schema contract).  
**Prerequisite already live:** migration `20261023030213_shared_ledger_context_identity_binding_v1` (one-to-one nullable `canonical_context_entity_id` with guards).  
**User-approved direction:** a Ledger's Reality context identity exists **under the hood** and is established as part of the **single governed Ledger creation operation**, never as an extra person-facing task.

## Functional promise

An authorized practitioner creates a *new* Ledger through the existing `ledger.onboarding_cases` process. When the case becomes `ready_to_activate`, the **same transaction** that inserts the Ledger will:

1. Run the current `ledger_activation_guard_v1`, locking and validating the onboarding case, its owning subject and assigned practitioner/legacy-adjudicated source.
2. Create **one canonical `reality.entities` identity of kind `ledger_context`** for that exact new Ledger UUID, with stable key `ledger_context:<Ledger UUID>` and a nonrevealing generic display name.
3. Assign the freshly created context entity UUID to `NEW.canonical_context_entity_id`.
4. Pass through the existing `ledger_canonical_context_identity_guard_v1`, which locks and confirms that Reality identity is canonical, distinct from the owning business and keyed to precisely this Ledger.
5. Complete the usual `ledger.ledgers` INSERT; the existing AFTER INSERT trigger marks the onboarding case completed.

Postgres runs same-kind BEFORE INSERT triggers in **name order**. The ordered trigger contract is **activation_guard (a) → binding_context_identity (b) → canonical_context_guard (c)**. This is a behavior-bearing part of the source review; if the trigger names/order change, review again.

If any operation fails—including the native Ledger insert, unique key or FK—the Reality identity birth rolls back in **the same transaction**. No pending orphan context and no double ownership of the same identity.

The caller never supplies `canonical_context_entity_id` for a *new* Ledger; attempting to spoof an identity fails. Once established, existing immutable binding guards remain in effect.

## Identity and jurisdiction

- `ledger.ledgers.subject_entity_id` **still denotes the real owning business/institution**, not the context entity.
- The new `ledger_context` Reality identity is an **addressability anchor** for the Ledger context. It is **not** a new duplicate of that business, not a second user-facing Ledger, and not a person.
- One business may legitimately have multiple Ledgers. Every Ledger receives **its own distinct context identity**, never a Person→Business relationship shortcut.
- The display name `Ledger context` contains no private Ledger name, person, email, medical content or onboarding evidence. The Ledger's own `name` remains in the Ledger custody.
- Creating this identity is **not** a person-to-Ledger Connection, entitlement, consent, verified ownership, seat, assignment or permission to read private actions/health records.
- No role/schema/table grants, RLS change, direct client RPC, user account creation, new relationship table/kind or propagation to another Ledger.
- `SECURITY INVOKER` means the calling governed Ledger activation path must already have privileges to write Ledger and Reality; it may not be made SECURITY DEFINER as a permissions workaround.
- Existing identity state adjudication/contestation can make a bound identity disputed or retired; any later universal Connection writer must reject noncanonical endpoints.

## Existing Ledgers and future adoption

**Zero automatic backfill.** The three existing real Ledgers and their current ten native Seats are not touched. They require a separately reviewed, source-matched **identity establishment and binding adjudication**; do not rely on their owning business Entity as the Ledger context.

Current users see no extra setup step for future Ledgers. Actual UI integration or user-facing onboarding changes are intentionally not in this phase: the canonical activation flow must be confirmed by app tests after release. Atlas's canonical single-Connection writer remains a separate, governed build.

No legacy `atlas.organizations`, `atlas.principals`, `atlas.organization_memberships`, or physical employee-seat authority is introduced.

## Review / verification

- The candidate is reviewed as a shared cross-domain machinery change, *not* a routine Atlas data transaction.
- Use canonical `noel-core-db` migration generation only **after** source review/merge.
- Validate on **disposable production-schema clone**, never the live DB:
  - native synthetic practitioner onboarding activation for two Ledgers with same owning business;
  - two different canonical Ledger-context identities, both correct kind/state/key, and cases completed;
  - unready onboarding cannot create a Ledger or an orphan identity;
  - an attempt to inject an identity UUID is rejected without creating another identity;
  - failed transaction discards even successfully created synthetic Ledger/Reality objects;
  - triggers execute in the intended order and do not expose helpers to `anon`/`authenticated`;
  - inherited live user Ledgers/Seats and permissions remain unchanged.
- The clone-only `postconditions.sql` uses genuine tables and an exception subtransaction to discard all synthetic data; it contains no real names/records.
- After a reviewed generated migration passes a protected clone and the principal **separately authorizes** production release, use only the protected `Production Database Release` workflow with live custody checks and exact version.
- Post-release verify a new properly authorized Ledger activates with exactly one context identity **in a separately authorized test/real onboarding**, without inventing a new real Ledger for demonstration.

## Deliberate stopping point

This candidate establishes the missing one-operation identity rule for **future** Ledger births. It **does not** yet establish previously existing Ledger identities, convert native Seats to canonical Reality relationship edges, or grant a new Ledger any particular human participant. Those belong to the next phases of the universal Connection engine and need authority/provenance and privacy proof independently.
