# Atlas known-zero weekdays with explicit public API grant custody (v2)

Source-only. Supersedes the unmerged/unreleased v1 generated PR #1658 (20261016211238) without modifying its immutable version.

Native Person capacity business logic and table source are copied from reviewed v1 source (PR #1656). A new guarded migration also reasserts the **existing, verified** public capacity proxy ACL: authenticated EXECUTE, anonymous denied, without expanding roles. The production-schema dump/restore used by the disposable clone did not preserve the public wrapper ACL, so the v1 behavior proof passed but the separate privilege assertion observed a clone-only anonymous EXECUTE grant. Attempting GRANT/REVOKE in a fixture was correctly rejected: the test harness only permits DML in fixtures. This v2 corrects at the **owning migration boundary**, and the synthetic fixture stays pure DML.

The unchanged positive interval behavior is preserved. Explicit confirmed-unavailable weekdays have zero capacity and NULL temporal starts/ends; no fake interval or blocks. Missing weekdays remain unknown. Source conflict, stable-key idempotency, authorized Person access and seven-day mixed weekly planning are tested by the same postconditions from the diagnostic v1 run #38968560247, now with a strict concluding anon/authenticated privilege assertion.

## Gate
New canonical migration identity → disposable clone structural+behavioral validation → explicit protected production release **only after approval**. No production DDL via connected SQL tools. Notebook PR #292 remains draft; its owner input grammar must ultimately distinguish available/unavailable/unknown without overwriting sources. Issue #1649 tracks this.