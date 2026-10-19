# Native Ledger workspace — seat-safe read boundary (Slice D0)

Source-only Atlas migration candidate. No native Ledger seat or other production entitlement is created.

## The specific defect

The previously released ledger_workspace_self_api_v1 checked only for an active native Ledger seat and then returned up to 100 otherwise-unfiltered ledger.actions, independently of root/worker access. For Elm Flowers, future seat participation by Anna would make historical native Ledger action titles/details reachable through a direct authenticated RPC regardless of the notebook UI.

## Remediation

- Preserve exact root-governing owner's existing workspace details by moving the old implementation into a private internal function whose EXECUTE privileges are revoked from PUBLIC, anon, authenticated and service_role.
- Recreate the original atlas RPC signature as a SECURITY DEFINER *least-privilege facade*, with an active-seat check, current canonical subject check, and independent current root governing authority proof.
- A seat holder **without** current root authority gets only the same Ledger identity and empty source/action/finance/customer arrays. The full historical reader is not even executed in that path.
- Replace the public wrapper with SECURITY INVOKER, and explicitly constrain all grants.

This breaks the incorrect implication that a Ledger seat grants every Ledger record. It does not yet establish legitimate worker-level Work visibility or legal read/record/manage/approve permissions; these require separately scoped projections over canonical Work and its verified institutional agreements.

## Mandatory acceptance before ANY worker seat

Direct-API authenticated tests must prove: current root sees permitted owner history; non-root seat sees Ledger identity but zero history, sales or customer detail; unauthorized/non-seat Person is denied; revoked seat is denied; one Ledger seat does not open another Ledger; spoofed JWT user metadata has no authority effect. Also inventory other exposed Ledger RPCs and legacy farm data readers for independent leaks.

Postconditions test name/grant/source boundaries but **cannot prove** this entire runtime matrix. Until it passes on a disposable production-schema clone and an authorized worker test account, do not grant Anna the native seat or claim the Build 5 security slice complete.
