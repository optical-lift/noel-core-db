# Atlas — Evidence-backed ordinary shared Work completion contract v1

**Status:** Governing build contract; source-read audit complete, implementation not released.  
**Established:** October 22, 2026.  
**Build priority:** Addition 2 — directly after source schedule-decision law, and before declaring the shared subject-work demonstration complete.

## 1. The user-selected behavior

**A person with lawful ordinary shared-work action authority can mark Work Done only by supplying an intelligible observation of what was accomplished.** Atlas must preserve who made that observation and separately who was responsible, who actually performed the work if known, and whether any independent evidence supports the claim.

A checkbox is **an interaction**, not evidence that the promised real-world state was achieved.

This does not mean paperwork or a photograph for every ordinary action. The default proof may be one small line of notebook ink: **“What happened?”** and a sentence describing the actual result.

## 2. Existing machinery and the verified gap

- Work identity and current state: `atlas.work_items`.
- Source context and institutional Ledger relevance: `atlas.work_item_context_links`, `atlas.company_work_native_ledger_relevance`.
- Source-owned historic result and acceptance: `atlas.work_execution_results`, `atlas.work_result_acceptances`, `atlas.work_result_contract_policies`.
- Current ordinary Event completion command: `atlas.mark_ledger_occurrence_shared_work_done_self_api_v1(organization_id,ledger_id,occurrence_id,work_item_id,source_action_id)`.
- Verified current v1 command writes an accepted `completed` result with `markedByPersonId` and explicitly **does not claim physical performer**. It accepts no outcome sentence or source receipt. Its evidence contains only marker identity and action ID, so it **does not satisfy the owner's evidence requirement**.
- Specialized Work (production, management acceptance, dedicated worker result contracts) has its own acceptance rules. Ordinary shared Work must not silently downgrade those requirements.

No Work duplication to a Person notebook. Completion evidence belongs to Work's original Organization/Ledger source; a Personal notebook is an authorized attention/read surface.

## 3. Minimal notebook sentence interaction

The default action is a single notebook-style sentence flow, not boxes or an AI-only prompt:

```text
Book music                    [Done]
What happened?
  "The musician confirmed the date, time and agreed rate."
  [Record outcome]
```

The app may offer a dedicated field for performer or evidence link when useful, but a normal user should not have to complete a multi-field form for an ordinary task.

A mere restatement **“Done”** / **“I clicked complete”** / blank text is not an outcome observation and must not satisfy the contract. An outcome sentence is an **attestation**: it proves what the authenticated recorder asserted and when, not independently that the event took place. A provider receipt, message, photograph, signed handoff or other source evidence may elevate the claim. For commitments such as **booking music**, a provider's affirmative confirmation may be required before the booking itself is presented as confirmed.

## 4. Versioned command envelope — proposed, not yet live

```text
intent: ordinary_shared_work_completed_with_outcome_v2
actor:
  authenticated user and derived canonical Person
  exact authorized active Ledger relation and Work command grant
subject:
  Organization ID, Ledger ID, canonical Occurrence ID when applicable
  exact Work item ID, source Work contract
sourceActionId: stable idempotency key
outcomeObservation:
  required nonempty real-world result sentence
  source of observation: self_report | witnessed | source_record
  occurredAt: time of work when established; otherwise unknown
actualPerformer:
  optional explicit canonical Person ID; NOT inferred from actor or assignee
sourceEvidence:
  optional list of exact authorized source refs / receipt ids
  specific proof standing (self-attested or independently corroborated)
proposedStateEffect:
  completed ONLY if this Work's actual result policy admits it
return:
  workItemId, accepted result ID, decision/acceptance ID
  actual actor, evidence standing, current Work state, replay status
```

`v2` describes a new operation contract, **not** permission to mutate the v1 signature in place or to update accepted history. Maintain separate command versions until reviewed cutover.

## 5. Required transition rules

1. **Exact source**: authenticate current Person, active Ledger and Organization relation, source Work identity, allowed state, and ordinary-work policy. Reject cross-Ledger work and specialized Work even if a UI renders their Done mark.
2. **Preflight**: inspect the current Work state and any consequential domain result contract. Distinguish ordinary checklist confirmation from externally verifiable promises, payments, safety and regulated or high-stakes work.
3. **Accept evidence**: the sentence must describe the state change or achieved result. Validate length, nonblank normalized content and idempotency. Do not assume length alone establishes truth.
4. **Record append-only attestation**: authenticated recorder Person, exact Work ID, source action ID, observed outcome, asserted time and optional independent source refs. Capture actual performer only if explicitly stated by someone with legitimate evidence.
5. **Decide acceptance according to source policy**: ordinary low-consequence self-attestation may be immediately accepted; higher-consequence Work remains `reported`, `needs_review` or the source's analogous state until corroboration/authority. A click must not bypass specialized result-adjudication logic.
6. **Apply Work transition atomically** with result/acceptance record where supported, retaining concurrency guards and idempotent replay. Never mark the source Work `completed` when its required evidence/acceptance did not pass.
7. **Show history accurately**: `Recorded by Katie`, `Reported performer: Marshall` only when independently asserted, `Outcome: ...`, `Evidence: self-reported / source-confirmed`; correct later mistakes by additive corrective entries, not rewriting the old attestation.
8. **Keep obligation relation distinct**: offer/acceptance of responsibility and personal attention do not change the authority of a lawful shared-work actor to record a witnessed outcome. No employee-only seat path.
9. **No mass retroactive promotion**: existing v1 accepted checklist results remain historically labelled as state assertions with their original evidence standing; neither silently reclassify them as independently verified nor delete them.

## 6. Missing or disputed evidence

- If an actor has an observation but Work policy requires a provider confirmation, save a **reported outcome pending acceptance** through the source contract rather than falsely completing the booking.
- If actual performer is unknown, retain `unknown`; the recorder is still known.
- If someone disputes completion, use a source-supported re-open/correction mechanism with the earlier result preserved.
- Evidence from a communication or booking source must retain its own provider/source identity and cannot be created by wording in the task note.
- Privacy applies to outcome sentence, source attachments, and named performer even if ordinary Work title is visible to more connected people.

## 7. Acceptance matrix

1. Unassigned ordinary Event Work: authorized Person adds nontrivial outcome sentence; accepted result yields a single completed Work, actor and historical evidence.
2. Authorized Person who is not the responsible Person reports what happened: marker distinct from performer, no fabricated personal performance.
3. Missing/whitespace/generic `Done` sentence: no completed transition.
4. “Booked musician” without required affirmative provider confirmation remains pending when booking truth is materially at issue.
5. Same action ID replay returns original result; same ID with materially different evidence is rejected (no idempotency laundering).
6. Two connected People submit competing completion evidence concurrently: result history and final source state remain coherent, without duplicated accepted completions.
7. Unauthorized Person, wrong Ledger, wrong canonical Occurrence, invalid source Work or specialized Work are rejected.
8. A blocked/retired Work item cannot be completed unless the owning state machine permits it.
9. Source receipts and note attachments preserve their original privacy, content hashes and provenance; no cross-Organization leakage.
10. Reopen and correction preserve earlier results and who asserted them, including evidence.
11. Both a personal attention view and a shared Ledger Event view reflect the one canonical source Work and its actual acceptance.
12. Same behavior in a second unrelated Ledger, with no Elm-specific template or hardcoded Person.

## 8. Implementation and release gate

**Gate A:** document the full v1 caller map (RPC, web UI, mobile interactions, automation) and inventory historical v1 result semantics.  
**Gate B:** establish narrow ordinary Work source policy, evidence admissibility and exact acceptance status; design v2 command, typed outcome standing and source-safe immutable result.  
**Gate C:** generate a reviewed Atlas migration and prove authorization, replay, concurrency, incorrect outcome, and specialized Work denial on protected disposable clone with real signed-transport follow-up.  
**Gate D:** implement notebook sentence UI and migrate all v1 caller paths; only after backward compatibility can the evidence-free v1 completion path be retired/denied.  
**Gate E:** three-Person + unrelated-Ledger live end-to-end proof; separate protected production release.

**Prohibition:** do not claim the present `mark_ledger_occurrence_shared_work_done_self_api_v1` already meets this contract.
