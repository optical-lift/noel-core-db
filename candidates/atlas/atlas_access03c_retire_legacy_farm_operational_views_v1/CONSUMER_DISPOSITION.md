# ACCESS-03C runtime function consumer disposition (source-only)

**Audited:** 2026-11-12; canonical source `optical-lift/noel-core-db`, Atlas governed as a universal Person/Principal/Organization/Ledger system. **Status: HOLD; no production deletion or permission change.**

## Governing distinction

The proposed deletion of four obsolete farm **views** cannot ship while living PL/pgSQL functions still reference them. `pg_depend` detects view-to-view dependencies but is not a complete census of PL/pgSQL SQL strings/rowtypes. A successful `DROP VIEW ... RESTRICT` is not evidence that such functions remain usable. Retain physical farm, Work, crop, Person, Ledger, history data; do not re-grant `atlas.zones` or resurrect a selected-farm Owner root.

The live `pg_proc` scan identified **10 directly dependent functions**, six with `authenticated` EXECUTE and four without. Current source body MD5 values are frozen as observations, **not approvals to preserve the old architecture**. Use `consumer_census.sql` to re-check schema/source drift read-only.

## Function-by-function disposition

| Function (all in `atlas`) | Current source MD5 | Auth EXECUTE | Known source-text consumer(s) | Disposition prior to 03C |
| --- | --- | --- | --- | --- |
| `farm_care_object_card_v1(uuid)` | `912250a84abe2680e98890862316f1c3` | No | `farm_care_object_v1`, `farm_care_zone_v1` | **Preserve until cutover**; part of a live callable care API's rendering |
| `farm_care_summary_v1(uuid,integer)` | `48a41b97be1f51ce7aa7a12422777bf6` | Yes | Listed by owner effective-disclosure review | **Preserve or replace by explicit care source contract**; do not silently drop |
| `farm_care_zone_card_v1(uuid)` | `36fe032b49403d4978385f24fb6b5822` | No | `farm_care_summary_v1`, `farm_care_zone_v1` | **Preserve until cutover**; internal care helper |
| `farm_care_zone_v1(uuid,text,integer)` | `d83dd57420af32defe491a3d1ece7b1b` | Yes | Listed by owner effective-disclosure review | **MUST preserve contract**: 03C itself requires this RPC to survive; rewrite its data source or explicitly govern replacement first |
| `tending_bed_v1(uuid,text,text)` | `c9311300e2b5fb0bef2e0db5f87bca2d` | Yes | Listed by owner effective-disclosure review | **Retirement candidate**, held for external/client compatibility and signed tests |
| `tending_board_v1(uuid,text,date)` | `2ad9b2467a2102e86ada62eb0cc5ae39` | Yes | Listed by owner effective-disclosure review | **Retirement candidate**, held for external/client compatibility and signed tests |
| `tending_card_json_v1(uuid,jsonb,boolean)` | `510f783e3162b1052b6081fb8fa3271b` | No | `tending_task_context_v1` | **First paired retirement candidate** with context v1, not safe to drop independently |
| `tending_card_json_v2(uuid,uuid,jsonb,boolean)` | `5621f5f54676f0310f54ea726cf7340e` | No | `tending_bed_v1`, `tending_board_v1`, `tending_task_context_v2` | **Retain while callers remain** |
| `tending_task_context_v1(uuid,uuid,text)` | `26ca1f7a3d1a16f1fc5b1aed9f2fae42` | Yes | Listed by owner effective-disclosure review | **First paired retirement candidate** with card-json v1; verify no external caller and review contract update |
| `tending_task_context_v2(uuid,uuid,text,text)` | `48a972d24a0b168211fbde6d8e6eb5d0` | Yes | Listed by owner effective-disclosure review | **Retirement candidate**, held for external/client compatibility and signed tests |

**Related but not among the ten direct view callers:** `farm_care_object_v1(uuid,text,integer)` is an authenticated executable caller of `farm_care_object_card_v1`. The `owner_effective_subject_disclosure_review_self_api_v1` function contains six legacy RPC names as disclosure-audit **strings**, not demonstrated runtime invocations. Deleting those RPCs would require reconciling this governed inventory and the Atlas counterpart `lib/governor-effective-disclosure-source.mjs`, not simply removing the strings to turn a test green.

## Current Atlas application evidence

[Atlas draft #569](https://github.com/optical-lift/atlas/pull/569) recursively inspects 432 active JS/TS files: the four obsolete **view** names have zero literal callers; the ten **function** names occur only as six audit strings inside `lib/governor-effective-disclosure-source.mjs`. [Scoped active-source contract #43313596005](https://github.com/optical-lift/atlas/actions/runs/43313596005) PASS. This **does not prove** absence of dynamic SQL, older deployed apps, external scripts, non-Atlas clients, or historical users. Do not claim function deprecation from string-only search.

## One first bounded cutover / retirement decision

Audit `tending_task_context_v1` and `tending_card_json_v1` together as a **source-only candidate for eventual deletion**; neither is a Principal root. First establish external/historical absence and all dependent code paths, then build the exact fail-closed canonical function-source unit and test it on a protected disposable current-schema clone. Verify signed authorized governor positives through current canonical Work/Bed/zone APIs, old manager/outsider/no-seat/anon denials, no-loss for crop/Work/history, and no change to the owner disclosure-review inventory until its replacement contract is separately accepted. No source-only scan alone authorizes `DROP FUNCTION`.

Care reader cutover is a separate bounded unit and must preserve `farm_care_zone_v1`'s supported result or supply an accepted native alternative. The existing 03C `DROP VIEW RESTRICT` candidate remains intentionally blocked until all ten function-body references are gone and the external/contract gates are satisfied. ACCESS-03B governed two-table RLS remains a separate prerequisite requiring its own protected release; no 03C deployment before it.

**No production DDL, RLS/grant change, data mutation, merge or outsider invitation is authorized by this inventory.**
