# Atlas Security Surface Baseline — 2026-09-02

Project: Supabase `noel-core` (`zirqkouammpwxlqfbsvf`)

Captured after migration `20260902223739_atlas_security_immediate_surface_hardening_v1`.

## Post-hardening counts

- Atlas functions executable by `anon`: 2
- Atlas functions executable by `authenticated`: 509
- Atlas functions executable by either `anon` or `authenticated`: 509
- Authenticated-executable Atlas `SECURITY DEFINER` functions: 500
- Atlas relations with any SELECT/INSERT/UPDATE/DELETE privilege for `anon`: 17
- Atlas relations with any SELECT/INSERT/UPDATE/DELETE privilege for `authenticated`: 197
- Atlas relations with any such privilege for either role: 197
- Authenticated-readable Atlas views: 18
- Authenticated RPC registry drift after hardening: 0

## Immediate closures recorded by this baseline

- `atlas.source_custody_release_packet_v1()` is no longer executable by `anon` or `authenticated`; it remains executable by `service_role` and is classified `service_internal` in `atlas.authenticated_rpc_registry`.
- Direct authenticated SELECT was revoked from:
  - `atlas.crop_cycle_yield_forecast`
  - `atlas.flower_demand_coverage_v1`
  - `atlas.flower_demand_line_position_v1`
  - `atlas.principal_authority_position_v1`

## Manifest files

- `functions-001-200.csv`
- `functions-201-400.csv`
- `functions-401-509.csv`
- `relations.csv`

The function files list every Atlas function executable by `anon` or `authenticated` at capture time. Columns are:

`kind,signature,security_definer,anon_execute,authenticated_execute,service_role_execute`

The relation file lists every Atlas table/view/materialized view with SELECT, INSERT, UPDATE, or DELETE access for `anon` or `authenticated`. Columns are:

`kind,relation,anon_select,anon_insert,anon_update,anon_delete,authenticated_select,authenticated_insert,authenticated_update,authenticated_delete`

This baseline is descriptive, not an allowlist. The clean Atlas rebuild should reduce and adjudicate this surface rather than preserving it automatically.
