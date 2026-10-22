# Atlas Household care-result public API — source-only candidate

This is a narrow **browser transport membrane** for a care event on an existing
active Household space. It is **not** a Household rhythm-completion command, not
an assignment/task writer, and not an API to declare a weekly need satisfied.

## Why this exists
- The current browser can read the verified Household care snapshot through
  `public.principal_household_care_snapshot_v1()`.
- The canonical result writer currently lives only at
  `atlas.principal_record_household_care_result_api_v1(jsonb)`. Calling it
  using the default public PostgREST RPC schema is not a released API.
- The app's H8 care form is feature-gated until this bridge is released by
  protected database custody and its API availability has been tested.

## Existing source owns all semantics
- Actor: authenticated principal, active household, existing active space.
- Request: `p_payload` with `spaceId`, `resultKind`, `conditionAfter`,
  stable `sourceKey`, optional `minutes`, `minutesKnown` and `note`.
- Existing enums for actual care results include `improved_more_remains`,
  `recovered`, `condition_differed`, `blocked`,
  `strategy_should_change`, `plan_changed_not_relevant`.
- Result writes attributed `care_result_events` and source-linked
  `care_observation_events` and preserves retry identity.
- The UI requires result/observation IDs and matching Household/space readback.
- No new tables, labels, recurrences, rights or inference engines.

## Deployment custody
Candidate only. Source generation requires a committed candidate on canonical
`noel-core-db` main and an owner-authored migration generation request.
Validation is against a disposable production schema clone; actual release is
separately protected and manual. Do **not** apply this candidate using live
Supabase `execute_sql`.

Post-release: independently verify the PostgREST browser RPC and legitimate
signed-in Household cases before enabling
`NEXT_PUBLIC_ATLAS_HOUSEHOLD_CARE_RESULT_WRITER_V1=enabled` in the app
environment. The flag is OFF by default, even when the code is merged.

## Rights negatives to verify
Anonymous caller denied. Signed-in member without owning Principal denied.
Cross-Household space ID denied. Inactive space denied. Bad result/condition
denied. Identical sourceKey retry returns same event; different retry payload
cannot overwrite the first. A partial-care result must not close the
Household rhythm or generate a fake Done.
