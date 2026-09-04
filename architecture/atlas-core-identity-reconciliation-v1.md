# Atlas Core Identity Reconciliation v1

**Status:** Database implementation note for Atlas Reality Foundation #788  
**Consumer:** `optical-lift/farm-atlas`  
**Database authority:** `optical-lift/noel-core-db`

Atlas Core identity is implemented as an evidence-first reconciliation substrate, not a canonical Party directory.

The durable identity anchor is a thin tenant-scoped subject UUID. Provider, legacy, imported, communication, route, and user-reported identity records remain source evidence. Names, aliases, contact coordinates, provider IDs, and person/organization/place classification are claims or projections over reconciled evidence.

The canonical migration for this version is:

`supabase/migrations/20260904204000_atlas_core_identity_reconciliation_contracts_v1.sql`

It introduces the Core subject/evidence/assertion/review/adjudication/projection surface plus governed identity reads and human review. Identity review distinguishes Same, Different, and Not enough evidence; insufficient evidence remains unresolved rather than becoming a false non-match.

The migration deliberately has no `local_intel` foreign-key dependency. Smart Contacts / Elm Local may contribute source evidence later through the integration/Receive boundary, but it does not own Atlas identity.

Canonical production-clone postconditions live at:

`validation/migrations/20260904204000_atlas_core_identity_reconciliation_contracts_v1.sql`

No broad Elm Farm identity backfill is part of this migration. Progressive source binding and migration of existing buyer/contact evidence remain later Reality Foundation work.
