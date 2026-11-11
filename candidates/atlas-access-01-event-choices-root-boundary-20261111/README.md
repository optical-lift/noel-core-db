# ACCESS-01 — Event access is not a roster or unrelated Work search

**Status:** unmerged security candidate; no production permissions, migration, signed actor tests or UI acceptance implied.

## Current source evidence (November 11, 2026)

The installed `atlas.ledger_occurrence_shared_work_actor_self_v1` correctly permits current exact-Ledger roots or Persons with explicit Event-identity disclosure to open the selected Event. Both `ledger_event_attention_people_self_api_v1` and `event_existing_work_choices_self_api_v1` reuse that helper but also return information **beyond that Event**: the first returns the active Ledger personnel roster, and the second returns open unrelated Ledger Work choices. Event disclosure alone is not a personnel-directory or other-Work read grant.

## Bounded proposal

In these **two** existing Atlas SECURITY DEFINER functions, retain the original exact Event identity/access helper and additionally call `atlas.capability_root_authority_context_self_v1(p_ledger_id)` **before** querying a roster or other Work. This checks the current signed canonical Principal and `root_governing` authority for the *same exact Ledger*. Do not infer authority from Organization owner, other Ledger root, seat, Work allocation, Event identity grant, or historical role.

No changes to `atlas.ledger_occurrence_shared_work_self_api_v1`, `atlas.ledger_occurrence_shared_work_actor_self_v1`, Event identity reader, existing Event-linked Work assigned-reader, any original Person/Work/Event, existing data, public facades, GRANT/RLS, Titus, Atlas app or production release workflow.

## Acceptance before release

1. Exact source and existing public wrapper argument/return/EXECUTE contracts unchanged, with only the two new root checks; regression structural postconditions pass in disposable current-schema clone.
2. Signed **root of Ledger A** with source-bound Event reads both choice functions; current returned packet shape intact.
3. Signed **Event-only Person on Ledger A**, with genuine identity disclosure but no root, can still read the permitted Event and their independently authorized linked Work; both broader choice functions return 42501 with zero Personnel or unrelated Work data.
4. Signed ordinary seat without Event permission, unrelated outsider, wrong-Ledger root, revoked/expired authority, other Organization Person and anonymous actor are denied, including direct public RPC and pagination/count/metadata probes.
5. Recheck independent Event-owned contextual readers and remaining alternate legacy readers before calling ACCESS-01 complete. Explicitly record any separate routes (including `direct_ledger_event_work_attention_self_api_v1`) requiring distinct authorization review rather than claiming this two-function fix closes them.
6. Separately authorize canonical migration generation, protected genuine signed schema-clone testing, migration/release, and browser testing. Do not expose or import private user rows as fixtures.

**Owning work:** Atlas #445, Noel #2409, Atlas #437, existing Atlas integration completion register and human acceptance issue #556. This is one limited source fix, not a claim that outsider admission is ready.
