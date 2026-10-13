# Personal bill source read and human interpretation consent

**Status:** candidate source only; not installed in production.

An owner-scoped personal bill recognizer may consume structured email observations only after all of these independently hold:

- An active Principal owns the existing Connected Source as `custodian_user_id`. An Organization-owned source is not an individual's household-finance connection.
- The provider/transport genuinely supports communication capture, is connected and not revoked, and holds an actual provider/capture read scope. `granted_scopes` records provider/transport access, **not** a grant of Atlas financial interpretation.
- The adapter has declared a real `personalBillRecognition` capability in addition to `communicationCapture`.
- The human owner has separately opted in to Atlas financial-interpretation consent, preserved as an actor-bound, action-keyed receipt in the Connected Source's non-secret metadata. This consent may be revoked independently of the provider's authorization.
- Only a source-native, structured `billNotice` field from an authenticated observation can be returned. The read projects an explicit field allowlist and does not return email bodies, attachments, or miscellaneous source payloads.

The proposed user-facing command `set_personal_bill_recognition_consent_self_api_v1` changes **only Atlas interpretation consent**, not the provider OAuth/API scope, provider connected status, source ownership, payable Money state or Clock. It has bounded idempotent replay and cross-owner denial.

Source observations remain evidence-only. The first recognizer produces possible bill notices and narrowly scoped clarification candidates, not a debtor, amount payable, paid status, payment instruction, or recurring owner obligation.

There is currently no proof that a Personal Atlas user has a connected *personally owned* eligible email source. A separate provider authorization and ingestion implementation is required before ordinary Foundry users can see real candidates.
