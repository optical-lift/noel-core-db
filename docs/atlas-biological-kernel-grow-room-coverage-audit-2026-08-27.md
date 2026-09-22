# Atlas Biological Kernel — Grow Room Coverage Audit

Date: 2026-08-27
PR under test: #64 `Atlas: establish pure biological kernel boundary`
Scope: read-only production-shaped evaluation of every active crop-cycle body currently attributable to the Grow Room / Grow Room propagation lineage. No production mutation, task release, or Home/Day change.

## Result

The v1 kernel contract sees **35 active Grow Room / Grow Room-lineage crop-cycle records**.

Current classification under the PR #64 rules:

- 19 → `observe_seedling_progression`
- 5 → `transplant`
- 1 → `observe_emergence` with a germination timing model gap
- 10 → `observe_and_reclassify_uncovered_state`

This proves the kernel does not silently lose the Grow Room inventory, but it is **not ready to merge as the biological authority yet**. State-vocabulary coverage and seedling-stage timing are incomplete.

## Five bodies correctly recognized as transplant work

The kernel independently recognizes these from biological state alone:

- Lacinato kale — `hardening_off` → `transplant`
- Fall lettuce mix — `hardening_off` → `transplant`
- Fall spinach mix — `hardening_off` → `transplant`
- Strawflower — `hardening_off` → `transplant`
- Mixed zinnias — June 23 tray batch — `hardening_off` → `transplant`

No destination or task state is needed to establish that transplant is the biological operation.

## Nineteen bodies recognized only as generic seedling progression

The kernel returns `observe_seedling_progression` for:

- Purple basil
- Fall cabbage mix
- Creeping thyme Box 1
- Creeping thyme Box 2
- Purple echinacea
- White Swan echinacea
- Tetra feverfew
- Sutton's Apricot foxglove
- Violet salvia
- Shasta daisy
- Chantilly series mixed snapdragons
- Potomac Berry Blend F1 snapdragons
- Rocket Mix F1 snapdragons
- Snow in Summer Box 1
- Snow in Summer Box 2
- Sweet William Box 1
- Sweet William Box 2
- Golden yarrow Pot 1
- Golden yarrow Pot 2

This is safe—none disappear—but too coarse for Atlas's governing purpose.

The current `crop_profiles` timing model has germination and harvest timing but no general canonical seedling→hardening→transplant timing fields. Therefore the pure kernel cannot yet lawfully infer when these cohorts should advance without a new observation or an external/manual state transition.

This is a central coverage gap. Atlas was built specifically so the owner does not have to stand in the Grow Room and notice that a transplant is getting old enough to plant.

## One pre-emergence body with model gap

- Pink perennial coreopsis — `sown_awaiting_emergence` → `observe_emergence`

The crop has no canonical expected germination boundary. Latest biological observation on 2026-08-02 was `germination_check / no_emergence_yet`.

The kernel correctly refuses silent waiting, but timing confidence is missing. This should remain an explicit biological-model gap, not become task-driven timing.

## Ten uncovered-state records

### Fall onion mix — `transplant_ready`

This is a severe vocabulary miss. Current crop metadata contains a 2026-08-25 field transplant-readiness observation of `ready` with ready_count 60, yet v1 does not recognize `transplant_ready` and therefore falls to generic reclassification.

Required kernel rule:

> `transplant_ready` is direct biological evidence that the transplant operation is due.

The current readiness evidence also exposes a custody issue: the newest readiness fact is stored in crop metadata rather than canonical `crop_observations`. The kernel should not require task state, but biologically authoritative readiness observations need a canonical source it is allowed to read.

### Greek oregano Pot 1 / Pot 2 — `germinated`
### Italian oregano Pot 1 / Pot 2 — `germinated`
### Rainbow Swiss chard Pot 1 / Pot 2 — `germinated`

All six have latest biological observations with stage `seedling`. The `germinated` cycle state is therefore a vocabulary mismatch, not unknown biology.

Required decision:

- either normalize `germinated` into the canonical seedling progression state when germination is admitted;
- or explicitly treat `germinated` as a seedling-transition state in the kernel.

Do not leave these as generic uncovered states.

### Lemon basil cuttings — `propagation`

Latest observation: 2026-08-02, stage `propagation`, condition `severe_loss_three_survivors`.
Crop metadata says three cuttings survive and the next biological question is rooting.

Required kernel coverage:

> propagation is a real living transition state with an observation such as `inspect_propagation_progress` / `inspect_rooting_and_survival`, not an unknown state.

Do not derive the operation merely from an old task. The physical propagation state and survival/rooting evidence must be authoritative.

### First Lady Mixed Colors snapdragons — `cleanup_needed`

Latest observation: stage `seedling`, condition `cleanup_needed`. Crop truth also records overcrowding/thinning need and some empty blocks.

Required kernel coverage:

> a physically compromised/crowded seedling cohort must produce biological intervention/inspection from the recorded physical condition rather than depend on an existing cleanup task.

The kernel should use biological facts such as crowding/thinning need; it should not make a task/action label itself the biological authority.

### July seed-start queue — `planned`

This is not a living crop body. It is an old aggregate planning record represented as an active crop cycle.

Required kernel behavior:

> distinguish non-living planning placeholders from crop bodies and do not treat them as biological inventory requiring observation.

Separate follow-up should reconcile/retire this aggregate pseudo-cycle after its child crop bodies are accounted for. Do not silently delete it during the kernel project.

## Major architecture finding: stage-transition timing is the next real gap

The Grow Room audit demonstrates that state vocabulary alone is not enough.

The pure biological kernel currently knows:

- germination timing;
- current crop state;
- current observations;
- harvest-watch timing;
- perennial stable dwell.

It does **not** have a sufficiently canonical model for:

- expected seedling-care duration;
- expected pot-up/space escalation;
- hardening readiness/window;
- transplant readiness/window;
- crop-specific age/size/container signals that advance those states.

Without that model, 19 current Grow Room bodies can only produce `observe_seedling_progression`, forcing a human to rediscover the biological state manually.

That would preserve truth but fail the primary product requirement.

The next kernel slice should therefore **not** be Home/task projection. It should first establish the canonical stage-transition policy/model needed to answer:

> Given this crop identity, sow/propagation date, container/state, and observations, what stage should Atlas expect now, and what biological operation becomes due if nobody supplies contrary evidence?

The model must remain below tasks, destinations, resources, weather, worker capacity, and presentation.

## Governing acceptance requirement from this audit

Before the kernel can become authoritative for Grow Room work:

1. every physically living Grow Room body must map to a covered biological state;
2. `transplant_ready` must yield transplant directly;
3. `germinated` must lawfully progress as seedling biology;
4. propagation must have a real continuation rule;
5. physical seedling problems such as crowding must create biological intervention/inspection without task dependence;
6. planning placeholders must be distinguishable from living bodies;
7. seedling→hardening→transplant expectation must be derived from canonical lifecycle policy strongly enough that Atlas can surface a transplant need **before** the owner notices it in the room.

No task, owner portal, planned occurrence, destination claim, resource gate, or Home/Day state may be required to answer that question.
