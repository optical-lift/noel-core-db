# ACCESS-03A: retire old direct farm-zone reads

**HELD SOURCE CANDIDATE.** No versioned migration, production write, or grant
change has been executed. Owner direction: retire the old permission software,
not real farm, Person, Work, crop, zone, or historical facts.

This candidate removes precisely one legacy `atlas.zones` SELECT policy,
the authenticated direct SELECT grant on that table, and the authenticated
SELECT grant on the `security_invoker` crop-cycle registry view. Its source
guard refuses drift in the live legacy ACL/policy, invoker shape, or the
current governed inventory/read function definitions. Internal sources and
all rows remain; the existing current connected-Person farm inventory is
authorization gated by canonical Person, Ledger and Subject disclosure.

Read-only live dependency catalog identified 11 views and 50 functions
mentioning zones. The view remains for internal readers; old direct
authentication surface, not data itself, is the retirement target. Deleting
the table or view would be unsafe while canonical and legacy internal
functions still consume them.

Required before promotion: protected full-schema disposable clone; genuine
signed GoTrue/PostgREST current governor, legacy manager without governing
Ledger root, outsider, and anonymous; no direct table/view metadata, ID,
count or existence leakage; positive guarded source read; preservation of
stored synthetic zone and crop rows. Local API must expose the atlas schema
for the adversarial test rather than misreporting 404/406 as a permission
denial. Review downstream old consumers and deliberate retirement scope.

Then use the canonical CLI-generated `atlas_` migration path,
reviewed exact source and explicitly authorized protected database release.
No live execute_sql mutation, no blind grant rewrite, no cascade.
See [Atlas #445](https://github.com/optical-lift/atlas/issues/445).

The generated-version full-schema clone starts with schema and roles, **not** fictional C1 data. The original 5-statement ACCESS-03A fixture relied on the separate Original Work fixture and failed intentionally at the first prerequisite assertion. This source-only repair prefixes the previously signed, DML-only C1 Original Work setup **verbatim through its legacy farm membership insert** (source blob `e877d93323ddc67d8778be8bea1dfa34319cc85c`), then runs the unchanged ACCESS-03A zone/crop fixture statements. Neither the approved migration SQL nor its postconditions change. This is a draft correction awaiting source/clone verification and owner approval; do not silently alter the earlier generated versioned PR or deploy it.
