# Native Ledger workspace — seat-safe read boundary (Slice D0)

Source-only Atlas migration candidate. No native Ledger seat or other production entitlement is created.

## The specific defect

The previously released ledger_workspace_self_api_v1 checked only for an active native Ledger seat and then returned up to 100 otherwise-unfiltered ledger.actions, independently of root/worker access. The existing ledger_entity_contexts_self_api_v1 independently trusts the seat to return Ledger-private entity contexts, contact routes, and the latest action payload. A third authenticated entrypoint, ledger_temporal_composer_self_api_v1, admits an active seat and assembles the entire Ledger's occurrence/calendar contributions, booking metadata and resource claims. For Elm Flowers, future seat participation by Anna could expose these sensitive facts through direct authenticated RPCs regardless of notebook UI.

## Remediation

- Preserve exact root-governing owner's existing workspace details by moving the old implementation into a private internal function whose EXECUTE privileges are revoked from PUBLIC, anon, authenticated and service_role.
- Recreate the original atlas RPC signature as a SECURITY DEFINER *least-privilege facade*, with an active-seat check, current canonical subject check, and independent current root governing authority proof.
- A seat holder **without** current root authority gets only the same Ledger identity and empty source/action/finance/customer arrays. The full historical reader is not even executed in that path.
- Replace the public wrapper with SECURITY INVOKER, and explicitly constrain all grants.
- Move the original entity-context reader to a similarly private internal function and make its public Atlas entrypoint require current exact root authority before invoking it. There is no generic safe worker projection of unrelated entity contacts or action payloads.
- Move the unrestricted Ledger temporal composer to a private internal function and require current exact root authority at its authenticated Atlas entrypoint, in addition to the original seat requirement. Delegated schedulers currently using this broad read may lose access until a narrower source-authorized calendar projection is built; that compatibility cost requires review, not a seat-based fallback.

This breaks the incorrect implication that a Ledger seat grants every Ledger record. It does not yet establish legitimate worker-level Work visibility or legal read/record/manage/approve permissions; these require separately scoped projections over canonical Work and its verified institutional agreements.

## Mandatory acceptance before ANY worker seat

Direct-API authenticated tests must prove: current root sees permitted owner history, entity contexts and calendar; non-root seat sees Ledger identity but zero history, sales or customer detail, and cannot invoke either the entity-context reader or broad temporal composer; unauthorized/non-seat Person is denied; revoked seat is denied; one Ledger seat does not open another Ledger; spoofed JWT user metadata has no authority effect. Also inventory other exposed Ledger RPCs and legacy farm data readers for independent leaks.

The clone-only `fixture.sql` supplies synthetic signed-in identity/session records, two native Ledgers, an exact root authority, a seat-only worker and a cross-Ledger member. The extended `postconditions.sql` tests the direct database-role/JWT-claim read matrix, including owner history, seat-only empty projections, denied entity/calendar/private readers, session invalidity, cross-Ledger isolation, spoofed user metadata, and transactional root/seat revocation. These exercises run only on a disposable schema clone; they do not prove cryptographic JWT verification or a real browser session. The resulting generated migration package must pass protected clone validation and independent signed-in API tests before any native worker seat. No current non-root native seat is available in production; do not create one while live D0 is unreleased.
