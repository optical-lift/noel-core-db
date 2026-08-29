# WNPH reconstruction execution job lane v1

This lane makes machine reading reconstruction a governed, durable operation instead of an ad hoc privileged HTTP action.

## Authority flow

1. A service-role caller creates an idempotent job through `public.wnph_request_reconstruction_job_v1`.
2. The request membrane resolves an active publication source package, an active target parent block in that package, and—when the target is a paragraph stream—an active governed semantic source span.
3. The request becomes a row in `wnph.publication_source_reconstruction_jobs`. No source observation, proposal, reading block, or canonical text changes at request time.
4. Supabase Cron calls `wnph-reading-reconstruction-runner` every 30 seconds using a Vault-held opaque runner credential.
5. The runner validates that credential through a service-role-only RPC. The incoming runner request can select only a bounded `max_jobs`; it cannot choose a publication, block, reading state, or reconstruction payload.
6. `public.wnph_claim_reconstruction_job_v1` claims one eligible job under `FOR UPDATE SKIP LOCKED`, creates an attempt row, and issues an expiring lease token.
7. The runner invokes the existing JWT-protected `wnph-reading-reconstructor` with the database-governed job parameters and forwards the already-validated opaque runner credential as an internal service-to-service authorization assertion.
8. The reconstructor retains `verify_jwt=true` and authorizes its handler through either the legacy service-role JWT role claim or the governed Vault runner credential validated by `wnph_validate_reconstruction_runner_token_v1`.
9. The reconstructor builds proposals from governed source packet v6 and calls `wnph_commit_reconstruction_batch_v1`.
10. Only the holder of the live lease token can finalize the attempt through `public.wnph_finish_reconstruction_job_v1`.
11. Retryable transport/worker failures return to the queue with bounded attempts; an abandoned lease is recorded as expired rather than disappearing.

## Reading-state boundary

This lane authorizes execution, not truth promotion.

An auto-admitted reconstruction remains governed by the existing reconstruction kernel. For the default `candidate` request state, successful execution can create candidate machine-derived blocks. It does not make those blocks source-verified, adjudicated, usable, or canonical. The existing canonical-text admission membrane remains downstream and unchanged.

## Security boundary

The dedicated runner has platform JWT verification disabled because Cron authenticates it with the dedicated Vault credential rather than a client JWT. That does not make reconstruction public:

- the runner requires an opaque high-entropy credential stored in Supabase Vault;
- the credential is validated by a service-role-only security-definer RPC;
- client roles have no table access to the job or attempt ledgers;
- client roles cannot execute request, token-validation, claim, or finish RPCs;
- the runner request cannot provide a source package, target block, or reconstruction payload;
- the runner forwards the same credential only to the JWT-protected reconstructor;
- the reconstructor independently validates that credential through the service-role-only validator before accepting the internal runner path;
- legacy service-role JWT callers remain supported when the Authorization token has the expected role claim.

The internal credential exists to bridge current backend secret-key transport semantics without exposing signing material or weakening the database custody membrane. It is not a publication capability and must never be exposed to a browser or author client.

## Custody and observability

Each job retains request authority/reason, attempt count, leases, errors, final reconstruction key, proposal statistics, database result, and worker response. Each worker attempt has its own immutable identity and outcome record.

The production installation was deliberately exercised inertly before publication work was authorized. Empty-queue Cron calls returned HTTP 200 with zero processed jobs.

The first governed Dewy Chapter II execution request is intentionally preserved as a failed attempt: the old reconstructor inner guard rejected current backend-key transport with HTTP 403 before any proposal was created. After source-custody merging the authorization bridge, a separate second job succeeded on its first attempt. That second job produced 26 auto-admit paragraph proposals and 26 `candidate` blocks, with 0 reviews and all 4 governed reading adjudications applied. Those blocks remain explicitly `machine_derived_not_source_verified` and are not canonical text.
