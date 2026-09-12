# Atlas Institutional Response Admission Policy v1

## Problem

Communication evidence and institutional obligation are not the same thing.

A direct message from a customer may reasonably enter Atlas's response-case workflow. A public social comment, reaction, broadcast, or provider system notice is also valid institutional communication evidence, but its arrival alone must not assert that a human is responsible for answering it.

The previous institutional ingest v3 admitted every incoming event with an external participant into response-case state. That made a Facebook Page comment structurally indistinguishable from a direct customer message for response triage.

## Authority rule

Provider evidence may describe the interaction form. Atlas owns the policy that decides whether that evidence is response-case eligible.

`communication_response_admission_policy_v1(event)` therefore returns one of:

- `response_eligible`
- `informational`
- `not_applicable`

The classification does not create responsibility. Even a response-eligible event only opens an **unclaimed** response case. Responsibility continues to arise only through Atlas claim/handoff rules.

## Fail-closed informational forms

The current policy suppresses automatic response-case creation for structurally public/informational forms:

- `public_comment`
- `reaction`
- `system_notice`
- `broadcast`
- legacy provider thread evidence beginning `comment:` or `reaction:`

The communication event and institutional conversation remain in custody and may still be viewed, searched, triaged, or acted on through later explicit Atlas authority.

## Conservative fallback

Unknown legacy interaction forms retain existing response-case behavior rather than being silently discarded. This policy only suppresses response cases when the evidence is structurally clear that the interaction is public/informational.

Provider adapters should increasingly emit provider-neutral interaction evidence in `source.interactionKind`; provider-specific thread prefixes remain a transitional compatibility seam.

## Truth boundaries

This policy does not:

- infer that a public comment is unimportant;
- mark a communication read;
- assign responsibility;
- close an existing response case;
- infer sentiment, urgency, legal status, HR sensitivity, or customer identity;
- alter provider evidence;
- delete or hide communication history.

It only answers the narrower question: **does the arrival of this communication, by itself, qualify to open/touch an institutional response case?**

## Deployment boundary

Source candidate only. No production database mutation, provider deployment, real account connection, Atlas application change, or Vercel deployment is performed by this candidate.
