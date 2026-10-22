# Atlas Personal Body Observation — First Source Build

**Status:** reviewed-source candidate only; no live release or user data writes.

## First real slice

- Reuse the **already released** Personal Reality raw capture, evidence, interpretation proposal, consumed human decision receipt and person-scoped Claim writer.
- Introduce an **owner-only longitudinal read** over those confirmed Claims, without a duplicate health writer, second observation store, or a link to Noel `practice.*`.
- The app's future `My Health` Index address will consume this membrane only after its protected release and authenticated acceptance.

## Expected existing Claim interpretation payload

These are contract examples, not a real person's record. The existing proposal API expects an array entry with `effectKey`, `effectKind: "claim"`, and `proposal`; the existing claim validator and human decision path govern application.

```json
{
  "subject": {"domain":"health","kind":"body_region","id":"knee:right"},
  "claim": {
    "claimType":"self_reported_symptom",
    "lifecycleState":"reported",
    "value":{
      "regionKey":"knee",
      "side":"right",
      "symptomKey":"pain",
      "reportedState":"present"
    }
  }
}
```

The specific location and symptom are **examples of a normalized candidate** for human correction, not a regex or hard-coded detection rule. The original person's words are preserved by the released raw capture independently of this payload.

## Date and count semantics

- `reportedAt` is the raw capture's recorded timestamp; `reportDate` is that instant on the caller-supplied validated timezone.
- `claimedEffectiveFrom/Until` are **not** inferred from the capture. They remain null unless a separately warranted explicit time was supplied and confirmed in the underlying Claim.
- The 30-day window is 30 **local calendar dates**, inclusive of today.
- `reportCount` counts distinct confirmed capture/region/side/symptom combinations; `distinctReportDates` counts dates. Neither is an episode count, an ongoing-duration count, a diagnosis or a causal inference.
- The reader returns at most 100 source-linked observations, a full within-window count and `truncated` so the UI cannot pretend truncated history is complete.
- A later body-domain validator must ensure valid anatomical region keys, laterality, and symptom vocabulary before app clients can automatically promote model proposals; this reader only consumes accepted shapes.

## Authority, release and non-scope

- Canonical owner: `atlas` personal evidence/claim machinery in the **noel-core-db** migration authority.
- App read seam (after release): `public.personal_body_observation_history_self_api_v1(integer,text,text,text)`.
- Write seam: **unchanged** `capture_personal_reality_self_api_v1` → propose `claim` → confirm with consumed human receipt → apply `claim`.
- This candidate does not authorize or implement an automatic interpreter, anatomical registry, diagnosis, principal capacity consequence, Clock admission, Noel research write, new Index address, or deployment.
- No private testimony, identifying health rows, third-party records, or founder research appear in this repo.

## Required verification before release

1. Disposable production-schema clone: apply this candidate and run its `postconditions.sql`; check Atlas lane security advisors and no new warnings.
2. Negative authenticated runtime: anon, foreign auth user and no active Personal Atlas must not read a person's observations.
3. Positive signed-in runtime: save a synthetic first-person symptom note; create a full existing Claim proposal; explicitly confirm/apply; verify exact source capture, region and laterality; reopen the 30-day reader.
4. Repeated reports: one input replay is idempotent; a second distinct report increments report count, not inferred episode count.
5. Time behavior: retroactive occurrence statements do not acquire invented onset; timezone boundaries preserve correct report dates.
6. Correction: a superseded claim no longer appears, but its underlying raw note remains auditable and unmodified.
7. UI admission and end-to-end human proof remain future app work; **do not call this first slice complete** merely because schema validation passes.

## Release order

Candidate review → source generation by existing owner-controlled workflow → disposable clone and scoped proof → separately authorized production DB release → Atlas app read adapter and Index presentation → signed-in user acceptance. No automatic Preview/Production deployment.
