# Atlas Personal Week Fit — read-only first connection

**Status:** candidate SQL only, not a generated migration, not clone-validated, not deployed. Initial source date: 2026-10-16.

## Source authority and dependency

This candidate implements **no separate scheduling authority**. It composes existing native Personal Atlas custody, household-owned events/rhythms, Person/Principal compatibility capacity day state, and user-owned Discovery answers. It introduces two read-only RPCs:

- `public.personal_week_planning_context_self_api_v1(p_week_of date)`
- `public.personal_week_work_fit_preview_self_api_v1(p_kernel_key text,p_week_of date,p_before_household_event_id uuid,p_estimated_minutes integer)`

Every call resolves authenticated `auth.uid()` to `atlas.current_person_id_v1()`, requires a single active native Personal Atlas, one exact compatibility Principal carrier and that Principal's active Household. No caller chooses Person, Principal, Household or other scope. Internal source readers remain revoked from `authenticated` and `anon`; `public` read proxies are authenticated-only, with fixed search paths.

The context runs `atlas.principal_capacity_day_state_v1` for **all seven local dates** (a released governed capacity evaluator), and returns source-referenced Household Events, Owner Obligations and currently dated Household Rhythm windows. It includes only two relevant approved Discovery answer fields and explicit source-coverage limitations. No raw household/Person tables are read by the app.

## Conservative provisional fit

For opt-in to existing `household.cleaning`, `household.laundry`, `household.groceries`, the preview compares capacity *only* after all seven local days report `capacityKnown=true`. With incomplete capacity it returns `capacity_anchor_required` and **no recommendation**. Recorded event, owner obligation, and rhythm window counts inform tie-breaking; unknown external source coverage and undocumented dependencies remain explicitly unknown. Estimated minutes are either caller-supplied **preview input** or a clearly unaccepted mean of available source kernel model estimates. Neither establishes a care requirement or duration.

If a real, same-Household, **fixed** event is explicitly supplied as a preparation anchor, only earlier dates qualify, and proximity to that date is evaluated as a disclosed heuristic. Atlas does not infer that an event is a guest visit or that Cleaning must precede it without an accepted relation. When no event is provided, no Friday guests or preparation chain are invented.

The response labels every proposed date `provisional_candidate_not_approved`. It contains the chosen local day, at most two alternatives, original source summaries, capacity provenance, and unknown-source warnings. It **does not** activate a kernel, mark its work executable, affect Clock admission, write an expected occurrence, or claim actual/complete care. Separate decision acceptance and source-owned recurrence placement still require governed source review.

This proof demonstrates one component of a Clock-owned **forward planning** seam, not full Shadow Schedule: it does not plan an entire portfolio, coordinate unverified cross-kernel dependencies, interpret external calendars as source truth, or replace current Principal Clock arbitration.

## Important conflict with current UI

Atlas PR #292's prototype still asks the human to choose Friday and writes a Household rhythm using the legacy `principal_upsert_household_rhythm_api_v1`. That must not be treated as Foundry's preferred behavior. The primary encounter should ask *whether the person wants that kernel maintained*, then use this read-only fit preview, disclose unknowns, and request acceptance. Manual weekday entry belongs behind an explicit override and must not quietly become the source of a recommendation.

## Validation requirements before promotion

1. Production-schema clone validates both SQL functions and PostgREST-facing proxies compile using existing live schemas.
2. Anonymous execution rejected, authenticated self-only, mismatched/non-native Atlas and missing active Household fail closed; one Person cannot select another Household's event by UUID.
3. Every returned event/obligation/rhythm belongs to the resolved source scope and the seven local calendar dates.
4. Missing all capacity policies returns `capacity_anchor_required`, no recommendation, including when Household has no events. One missing weekday must have the same result.
5. Known, sufficient, seven-day capacity yields a **provisional** recommendation. Estimated minutes source remains explicit. Under-capacity returns `no_fitting_window_in_known_capacity`.
6. Fixed event on Friday excludes Friday and later dates; all eligible known candidates must precede its verified local date. A foreign/non-fixed event UUID fails closed.
7. Event pressure is source observation only: no `fixedHouseholdEvents` record is created and no blank external calendar is interpreted as confirmation.
8. Source results, migration versions, tasks, Clock candidates, owner obligations, household rhythms, and `commitment_plans` row counts are unchanged by both readers.
9. Repeated source reads agree on stable references and day ordering within one frozen fixture.
10. Do not release without the separate reviewed noel-core-db migration-generation and production-schema clone validation lane. No paid Supabase preview database.

## Follow-up cut

Create a fully governed *accepted-decision/owning-domain write* seam after source-context acceptance is proven. Restore room-specific Household Cleaning requirement/satisfaction before implementing real Done or missed-week alerts. Add other canonical Temporal Contribution source adapters rather than cloning a task/calendar store. Keep Clock's current-day arbitration distinct from forward alternatives.
