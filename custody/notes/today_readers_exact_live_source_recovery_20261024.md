# 2026-10-24 Today reader production-source custody recovery

This is an **exact-live-body source restoration only**, not a new migration deployment and not a change to Today feature logic.

The protected shared Foundry release #2149 halted in GitHub Actions run #40131650933 before its SQL step because the global/live shared-lane custody verifier found these two **unclassified** already-executed production migration receipts absent from canonical Git:

| Supabase version | Name | Exact live Git blob SHA-1 |
|---|---|---|
| 20261024173945 | today_person_agenda_backlog_activity_readers_20261024 | 9f20381e2d32492acc1b3b8d3e2f9d579ce9d3c7 |
| 20261024175617 | today_new_readers_revoke_anon_execution_20261024 | 94a6d901a718fb7aba1ae1a02043685812aca588 |

Both original SQL bodies were independently recovered **read-only** from `supabase_migrations.schema_migrations.statements` on production `zirqkouammpwxlqfbsvf`, using `array_to_string(statements, E'\\n')`. A GitHub `fetch_file` read after each temporary file creation independently verified the resulting exact blob SHA-1 equals the live custody packet. The temporary files were then deleted from the migration directory because their historical names do not satisfy the approved migration-owner prefix rule. Instead, `custody/post-fence-migration-recoveries-v57.json` records those two exact immutable hashes as a sealed retrospective exception, with its own Git blob pinned in `scripts/check-custody.sh`. This does not claim recovery of an unavailable author's separate draft; it authenticates the *executed statement bytes* attested by the production migration ledger.

No synthetic SQL, replay, regenerated migration version, manual DDL, user data, secrets, or product behavior updates. Do not run these already-executed SQL files again.

Once source-custody CI independently confirms v57's sealed hash receipt and current live correspondence, the historical receipt may be merged without publishing or replaying a new unprefixed SQL migration, allowing the separately protected Foundry release gate to be retried. The Foundry migration remains under the separate protected database-release workflow and does not gain approval from this recovery alone.

## Completion of v57 canonical materialization

The sealed v57 historical exception by itself is not the final global custody state. After the registry was pinned and merged, Noel's global reconciler still classified the two live receipts as active-tail gaps because the policy's recovery range ended at v56. The v57 completion therefore (1) extends `recoveryRegistry.lastContractVersion` to 57, and (2) materializes the two *identical original executed-body Git blobs* into `supabase/migrations`. Each returned GitHub SHA-1 was independently checked against the original production receipt. The static owner-prefix checker now accepts these files **only** because v57 explicitly seals their filename + hash. A different SQL body or any new unprefixed filename remains prohibited.

These files are **already executed**; they are historical source custody, not new runnable migrations. This step must not replay them, change production data, or authorize later unprefixed migrations.
