# Atlas Development Build Spine v1

**Status:** Governing sequencing note for the Development domain candidate  
**Date:** 2026-09-22  
**Branch:** `architecture/development-domain-v1`  
**Purpose:** Preserve the exact build order for Development and prevent concurrent work from prematurely coupling Development to shared Atlas mechanisms that are still advancing elsewhere.

## 1. Current checkpoint

Development has crossed the architecture-design boundary and now has a concrete candidate kernel.

Current candidate artifacts:

- `architecture/atlas-development-domain-v1.md`
- `architecture/atlas-development-contracts-v1.md`
- `architecture/atlas-development-ci-washers-proof-v1.md`
- `architecture/atlas-development-elm-flower-preparation-proof-v1.md`
- `architecture/atlas-development-cross-domain-qualification-audit-v1.md`
- `supabase/migrations/20260922184500_atlas_development_kernel_v1.sql`
- `validation/fixtures/20260922184500_atlas_development_kernel_v1.sql`
- `validation/migrations/20260922184500_atlas_development_kernel_v1.sql`

The candidate kernel models:

```text
Development Standard Version
-> Development Case
-> Criterion Resolution history
-> Gate evaluation
-> Development Release
```

The cross-domain proof uses:

- Camps International / Washers;
- Elm Farm flower preparation / bunching.

The candidate remains unreleased until governed production-schema-clone validation is available and passes.

## 2. Freeze boundary

**Do not build Development Attention / Discovery executably yet.**

Do not add migrations, automatic Work creation, artifact ingestion, AI extraction, Decision Requirement orchestration, communication consequences, Qualification, Outcome Package behavior, or UI/runtime integration on top of the Development candidate before the kernel itself crosses its validation/release boundary.

Reason:

Development Attention deliberately depends on Atlas-wide mechanisms that are independently advancing:

- Company Work;
- Company Work institutional adjudication authority;
- Reality Transition;
- Reality Continuation;
- Reality Reconciliation;
- authority-required Decision Requirements;
- Reality Sentence / Reality Candidate custody;
- artifact interpretation;
- institutional Communication;
- Semantic Interaction Runtime.

Building against those seams while another tranche is changing them creates avoidable rebase and semantic-cutover risk.

The correct action during that overlap is documentation only.

## 3. Required gate before executable Development Attention

Resume executable Development work only after all of the following are true:

1. the Development kernel candidate has passed the governed disposable production-schema-clone validation;
2. its two-domain fixture proof passes without CI-specific or Elm-specific dependencies in the universal kernel;
3. the kernel migration has been deliberately released or otherwise assigned a stable executable contract;
4. current Company Work adjudication/Decision Requirement authority contracts are stable and documented;
5. current Reality Transition / Continuation / Reconciliation contracts are stable and available for consumption;
6. the Development branch can begin from current `main` rather than carrying stale copies of those shared mechanisms.

If any dependency has materially changed, re-audit the Development integration against the released contract instead of preserving an older assumption.

## 4. Next dependent tranche — Development Attention / Discovery v1

Development Attention is a **read/projection layer**, not a new truth root.

Its governing question is:

> **Given an open Development Case, which unresolved criterion deserves attention next, and what is the smallest lawful move likely to reduce the most important uncertainty?**

It should consider:

- exact unresolved Criterion positions;
- gate consequence: which release gates are blocked and by what;
- criterion prerequisites/dependencies;
- existing source coverage;
- already-admitted Claims/Evidence;
- inherited Company Operating Knowledge;
- information gain;
- expected human friction;
- reusable impact across other Development Cases;
- freshness/staleness of evidence;
- whether the missing motion is research, field testing, source recovery, or institutional judgment;
- whether a current actor with the required authority exists.

It should not decide the criterion.

## 5. Development Attention output contract

A Development Attention Candidate should be able to classify the next move into a small set of **handling families**.

Candidate families:

```text
recover_from_source
request_or_collect_evidence
commission_research_work
run_prototype_or_field_test
surface_authority_decision
reconsider_inherited_rule
wait_for_prerequisite
settled_or_no_action
```

These are routing descriptions, not executable command names.

The owning Atlas mechanism remains authoritative.

## 6. Native handoff map

### recover_from_source

```text
Development Attention
-> source/artifact interpretation
-> Claims/Evidence or candidate finding
-> Criterion reconsideration
```

The source adapter must preserve exact provenance.

Machine interpretation never establishes Development truth by itself.

### request_or_collect_evidence

```text
Development Attention
-> Claims/Evidence collection path
-> Criterion reconsideration
```

### commission_research_work

```text
Development Attention
-> Company Work Requirement
-> Work
-> Result
-> Evidence
-> Criterion reconsideration
```

The Development Criterion remains distinct from the Work item.

### run_prototype_or_field_test

Same Company Work/Evidence path, with a domain-specific test plan.

Completion of the Work does not automatically resolve the Criterion.

### surface_authority_decision

```text
Development Attention
-> Reality Reconciliation says authority_required
-> exact Development Decision Requirement
-> authorized human
-> bounded Development command
-> Criterion Resolution transition
```

No generic owner/manager shortcut.

### reconsider_inherited_rule

```text
Company Operating Knowledge changes
-> Development continuation
-> affected inherited Criterion reconsidered
```

Development must consume the existing Operating Knowledge resolver rather than inventing its own precedence engine.

### wait_for_prerequisite

A Criterion can remain unresolved without creating noise when another prerequisite must be resolved first.

### settled_or_no_action

No Work or decision should be created merely because a Development Case exists.

## 7. Ranking law

Development Attention should reuse the proven Reality Discovery pattern without reusing the Personal Reality Discovery tables.

A candidate scoring law may begin conceptually as:

```text
attention value
=
base importance
+ blocked-gate consequence
+ information gain
+ reusable impact
+ source-recovery opportunity
- expected friction
- unresolved prerequisite penalty
```

The exact weights are not constitutional truth.

The important law is ordering:

> Prefer recovering already-existing institutional knowledge before asking an expert to recreate it.

Then:

> Prefer delegable research/evidence work before escalating to scarce expert judgment.

Then:

> Surface expert authority only when evidence/research cannot lawfully resolve the institutional choice.

For CI this means Atlas should distinguish:

```text
"Find current washer prices."
-> delegable evidence work

from

"Which sufficiently tested portable pit design should CI canonize?"
-> authority-required institutional decision
```

## 8. Labor-reduction objective

Development Attention succeeds when it reduces expert reconstruction.

It should be able to identify patterns such as:

```text
Five activities are blocked only by current cost evidence.
-> create/recommend a shared pricing research campaign

Eleven activities may inherit the same projectile-clearance rule.
-> investigate one reusable Operating Knowledge standard

Three old source artifacts may answer this criterion.
-> inspect sources before asking David

Two tested alternatives remain and the evidence cannot select policy.
-> ask exact authority
```

The system's goal is not to make experts fill every field faster.

The goal is to **systematically reduce the number of decisions scarce experts still have to make**.

## 9. Development Campaigns come after Attention

A deliberate Development Campaign such as:

```text
Make 20 CI activities Buildable
```

should not become a new Development task system.

After Attention exists, a campaign can compose:

- selected Development Cases/gates;
- resulting Company Work Requirements;
- Commitment Plans;
- assignments;
- communication.

Campaign planning is downstream of criterion accounting and attention ranking.

## 10. UI/runtime comes after domain handoffs

Do not build a Development-specific dashboard first.

The desired user experience is eventually a governed projection inside Atlas's notebook/runtime.

Example:

```text
Washers

Playable        satisfied
Teachable       satisfied
Buildable       blocked by 2
Portable        needs evidence
Fundable        current cost missing
Replicable      blocked by 4
Trainer-ready   qualification standard unresolved
```

A visible unresolved Criterion becomes a SemanticTarget only after the source-domain command seams exist.

Examples:

```text
Cost basis — needs evidence
-> Add evidence
-> Create investigation Work
-> Inspect sources
-> Defer

Portable design — authority required
-> Review evidence
-> Decide
-> Keep unresolved
```

The runtime must derive these actions from domain contracts.

## 11. Later integrations — explicit order

After Development Attention is proven, build in this order unless a later architecture audit changes the dependency graph:

1. **Source recovery adapter**
   - promote the safe artifact-interpretation pattern outside Implementation;
   - preserve source/excerpt provenance.

2. **Company Work handoff**
   - bounded creation of research/prototype/test requirements;
   - no Work-result-equals-decision shortcut.

3. **Continuation/Reconciliation integration**
   - Criterion transition creates dependent gate reconsideration;
   - external evidence versus authority-required handling remains explicit.

4. **Development Decision Requirement**
   - exact authority membrane;
   - bounded decision command;
   - no role shortcut.

5. **Reality Sentence integration**
   - natural-language proposals resolve to Development commands where lawful;
   - otherwise remain candidate/unresolved.

6. **Development Campaign projection**
   - group common blockers across Cases;
   - reuse Commitment + Work.

7. **Notebook / Semantic Interaction projection**
   - Development becomes ordinary Atlas interaction, not an R&D silo.

8. **Qualification integration**
   - Trainer-ready or competency-oriented development may feed governed Qualification Standards after that domain is executable.

9. **Outcome Package integration**
   - released/qualified Development outputs become inputs to Package composition;
   - Package never becomes Development authority.

## 12. No speculative coupling

Do not add foreign keys from the universal Development kernel directly to:

- CI Activity tables;
- Elm flower tables;
- future Qualification tables;
- Package tables;
- implementation-specific artifact tables.

Use typed addresses/adapters until the two domains prove a genuinely identical executable relation.

Likewise, do not copy:

- Work;
- Evidence;
- Operating Knowledge;
- Communication;
- Money;
- inventory/resources

into Development-local shadow tables.

## 13. Resume checklist

When Development work resumes, the first session should:

1. read the released Development kernel contract;
2. read the then-current Company Work authority contract;
3. read the then-current Reality Transition / Continuation / Reconciliation contracts;
4. compare them to this spine;
5. update this spine if any shared seam changed;
6. build **Development Attention as a read projection first**;
7. prove its ranking/routing behavior against CI and Elm before allowing it to create any downstream Work or Decision Requirement.

## 14. Current stopping point

The correct stopping point for this conversation is:

```text
Development architecture qualified
+ candidate kernel written
+ CI proof written
+ Elm proof written
+ Development Attention build spine documented
---------------------------------------------
WAIT for kernel qualification / shared-mechanism convergence
```

No further executable Development tranche should be stacked onto the branch at this boundary.
