# Build 5 — Today institutional work transport

## Defect

The signed-in Atlas Today notebook calls `public.organization_work_accountability_self_api_v1()` over the default PostgREST `public` API. The released source function only exists under `atlas`, so PostgREST reports an unavailable RPC. Until the companion UI correction is released, Today silently treats that transport failure as an empty owner-work record and hides **Other work**.

## Candidate

Add one `public` zero-argument `SECURITY INVOKER` transport wrapper invoking the existing `atlas` source. Revoke all default rights and grant only `authenticated` EXECUTE. No creation of accounts, new seats, permissions, pricing, rows, positions, or worker responsibilities. No modification to the source function's active-owner membership check or sensitive result constraints.

## Verification

- Static postconditions require both signatures, authenticated-only EXECUTE, public invoker vs. source definer, and retained owner membership filtering.
- Disposable-clone test then signed-in API probes must verify owner work review, non-owner empty/denied institutional data, outsider and revoked owner isolation, anonymous rejection, and cross-Ledger privacy.
- UI should expose a recoverable source-unavailable state instead of equating transport failure with no work.
- The separate D0 Ledger seat-safe matrix is still a prerequisite for granting **any** new worker native seat.

## Release

Review source PR, merge candidate on canonical main, generate migration through the governed issue workflow, validate in the protected disposable clone, review release, and separately authorize production deployment. **Do not create a paid Supabase branch or test seat.**
