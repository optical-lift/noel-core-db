# WNPH reconstruction execution job lane v1

This lane makes machine reading reconstruction a governed, durable operation instead of an ad hoc privileged HTTP action.

## Authority flow

1. A service-role caller creates an idempotent job through `public.wnph_request_reconstruction_job_v1`.
2. The request membrane resolves an active publication source package, an active target parent block in that package, and—when the target is a paragraph stream—an active governed semantic source span.
3. The request becomes a row in `wnph.publication_source_reconstruction_jobs`. No source observation, proposal, reading block, or canonical text changes at request time.
4. Supabase Cron calls `wnph-reading-reconstruction-runner` every 30 seconds using a Vault-held opaque runner credential.
5. The runner validates that credential through a service-role-only RPC. The incoming runner request can select only a bounded `max_jobs`; it cannot choose a publication, block, reading state, or reconstruction payload.
6. `public.wnph_claim_reconstruction_job_v1` claims one eligible job under `FOR UPDATE SKIP LOCKED`, creates an attempt row, and issues an expiring lease token.
7. The runner invokes the existing JWT-protected `wnph-reading-reconstructor` with database-governed job parameters and the same governed runner credential. The reconstructor keeps platform `verify_jwt=true` and accepts either a legacy service-role JWT role claim or the Vault runner credential validated through `wnph_validate_reconstruction_runner_token_v1`.
8. The reconstructor builds proposals from governed source packet v6 using deterministic layout algorithm v5 and calls `wnph_commit_reconstruction_batch_v1`.
9. Only the holder of the live lease token can finalize the attempt through `public.wnph_finish_reconstruction_job_v1`.
10. Retryable transport/worker failures return to the queue with bounded attempts; an abandoned lease is recorded as expired rather than disappearing.

## Reading-state boundary

This lane authorizes execution, not truth promotion.

An auto-admitted reconstruction remains governed by the existing reconstruction kernel. For the default `candidate` request state, successful execution can create candidate machine-derived blocks. It does not make those blocks source-verified, adjudicated, usable, or canonical. The canonical-text admission membrane remains downstream and unchanged.

Source-image verification is a separate membrane. Candidate blocks can be checked through the governed source-block verification packet, but no verification result is valid merely because a source URL or OCR observation exists. Literal source-page inspection is required. Verification cannot edit text: a mismatch routes back to observation-level adjudication and reconstruction; only a candidate verified unchanged against all required source pages may cross canonical-text admission.

## Security boundary

The dedicated runner has platform JWT verification disabled because Cron authenticates with a Vault-held opaque credential rather than depending on a caller-supplied user JWT. That does not make reconstruction public:

- the runner requires the opaque high-entropy credential stored in Supabase Vault;
- the credential is validated by a service-role-only security-definer RPC;
- client roles have no table access to the job or attempt ledgers;
- client roles cannot execute request, token-validation, claim, or finish RPCs;
- the runner request cannot provide a source package, target block, reading state, or reconstruction payload;
- the reconstructor remains `verify_jwt=true` and separately validates either a legacy service-role JWT claim or the governed runner credential.

## Custody and observability

Each job retains request authority/reason, attempt count, leases, errors, final reconstruction key, proposal statistics, database result, and worker response. Each worker attempt has its own immutable identity and outcome record.

The production installation was exercised inertly with an empty job table before any publication reconstruction was authorized. The first real Dewy Chapter II job failed closed on the reconstructor's legacy JWT-shape guard and remains preserved as a failed attempt. After the source-custodied authorization bridge, a distinct candidate-only Chapter II job succeeded with 26 paragraph proposals, 26 auto-admissions, 0 reviews, and all 4 governed reading adjudications applied. Those outputs remained machine-derived candidates until a separate source-image verification membrane could evaluate them.
