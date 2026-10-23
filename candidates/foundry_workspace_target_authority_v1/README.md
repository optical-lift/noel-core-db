# Foundry workspace target authorization — isolated source candidate

**Status:** SOURCE-ONLY / not migrated, not clone-proved, not deployable.  
**Base:** stacked on [Foundry registry PR #2093](https://github.com/optical-lift/noel-core-db/pull/2093).  
**Companion:** [Foundry connected authority reference PR #2](https://github.com/optical-lift/atlas-ledger-foundry/pull/2).

## Why this exists

The existing Atlas delegated agent command system accepts Ledger-scoped and personal/either commands. It already handles active carrier credentials, Principal status, time windows, exact command allowlists, execution classes, confirmations and target-restricted delegated scope. **Its current target check does not look up Foundry workspace custody.** A caller-controlled target ID and JSON allowlist therefore cannot be treated as proof that the Principal owns a Foundry workspace.

This source candidate:

1. Extends only the `atlas.agent_command_definitions.scope_kind` check enum with `foundry_workspace` (not an alternate delegated-agent table).
2. Adds a Foundry-only rejection when a Ledger delegation attempts to run a Foundry command.
3. Extends the **existing** `evaluate_delegated_agent_command_target_authority_v1` for `foundry_workspace` commands. Requires exact target kind and exact command target contract; no Ledger/seat; both explicit delegated `targetKinds` and `targetIds`; existing *private* Foundry workspace registry row; **matching current owner Principal**; reviewed source custody with basis and reviewer; no suspension/revocation.
4. Does not activate any Foundry command or create a public endpoint, RLS policy, delegation or Ledger.
5. Leaves non-Foundry command decision paths identical to the installed code, except that a Ledger delegation now explicitly rejects the newly admitted Foundry scope.

Both function bodies were extracted from live `noel-core` on October 23, 2026, then changed only at these targeted decision branches. Before any protected release, reconcile the exact live function definitions again; do not overwrite a newer parallel identity/security change.

## Security and access boundaries

- A registered `scope_kind='foundry_workspace'` command may be **considered** only by the existing delegated-agent target evaluator. Registration alone is not authorization.
- No existing principal, agent token or Ledger permission authorizes another Principal's workspace.
- Pre-Ledger authorizations must be bound to a **specific** reviewed workspace. Null Ledger ID alone is not sufficient.
- The Foundry registry's provisional subject label is not a canonical Person or evidence of consent.
- Human operator and Principal ownership remain separate. This does not confer external subject confirmation authority, and no canonical Atlas Reality write is permitted.
- Historical pre-registry Foundry workspaces cannot be accessed by fabricating a registry owner. Reconciliation is a separate step.

## Validation required

Run in a *disposable production-schema clone*, using the existing Noel protected source → generated migration → full clone → manual release sequence:

1. Apply PR #2093's registry candidate first, then this `candidate.sql`, and run `postconditions.sql`.
2. Run rollback-only synthetic principals/carriers/command definitions/authorization fixtures covering wrong owner, wrong target kind, missing target IDs, unreviewed/revoked/suspended custody, Ledger-scoped agent, expired/revoked token, and valid reviewed pre-Ledger target.
3. Verify older `booking.request.*` Ledger command paths produce identical authority results before and after.
4. Verify all direct table/function grants and security-definer search paths, no unexpected RLS leakage.
5. Verify old Foundry events/snapshots remain intact, including legacy envelopes and snapshot lag. No backfill is authorized.

Until (2)-(5) pass in a full production-shaped clone, the code is **not proven against real DB behavior**. The `postconditions.sql` is a source/privilege guard, not a substitute for those tests.

## Remaining integration gaps

- No authenticated, server-adjudicated human **workspace creation/custody review command** yet; registry starts closed.
- No `foundry.*` command definitions registered or bound to handlers.
- No connected Foundry reducer, public operation API, MCP adapter, consent review interface or safe legacy resume bridge.
- No schema/production release approval.

**Do not merge into a migration or deploy as a user-facing capability solely because this PR exists.**
