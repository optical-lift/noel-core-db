# Noel: Song-first translation permissions inside the mark Reality Pool

## Canonical purpose

An attested MT Hebrew source token already resolves to a single exact-form NMF and a versioned consonantal NMI. Do **not** create a second lexical pool for each occurrence or merge the 287 founder-authored lexical pools. The private *translation Reality Pool* is a reader overlay keyed by NMI and further scoped to NMF, token occurrence, or tested state-transition when evidence requires specificity.

Song of Songs is the research priority for assigning a **Greek LXX translation anchor** to the Hebrew mark. The canon governs whether the proposed invariant actually works. Greek lemma indexing, Tiberian pointing, Strong's labels, and later dictionary categories are not controlling Hebrew mark identity. Preserve every original source surface and source provenance, including those later layers, as historical evidence without using them to decide identity.

The map is **bidirectional and lossless**:

- Song Hebrew source occurrence -> CATSS Song Greek token/lexeme (attested anchors, including Song-internal alternatives).
- Hebrew NMI -> all attested CATSS Greek choices, via a source-token-indexed mapping table.
- Greek choice -> every attested Hebrew NMI it translates; shared Greek cannot by itself collapse Hebrew identities.
- Proposed translation interpretation -> state-transition predicate, canonical support, counterexample, local scope and stewardship decision.
- Any MT token occurrence -> its private existing Reality context, Song anchors, LXX alternatives, and scoped permission assessments.

A Greek translation's historical **occurrence** never automatically means it is a canon-**permitted** interpretation. The absence of a translation in the surviving alignment is **not** evidence of its impossibility.

## Reality objects

1. `draft.noel_mark_lxx_choice_occurrences_v1`: observed CATSS Greek member linked to source Hebrew NMI/form/token and CATSS segment and target word, with evidence quality, source/target member positions and roles, segment cardinality and phrase-membership status. A one-to-many or many-to-many membership is *not* a direct lexical equivalence. Unique source/segment/target combination prevents cross-ledger duplication.
2. `draft.noel_mark_song_anchor_choices_v1`: identifies exactly which of those attested choices occur in Song; one direct Song lexeme can be marked sole observed choice, while multiple Greek Song words remain visible.
3. `draft.noel_mark_translation_constraints_v1`: provisional/confirmed **interpretation constraints** about a Greek choice for that NMI, optionally restricted to a form, occurrence or state transition. `canon_excluded` requires an actual steward decision and explicit before/operation/after plus contradiction basis. Mere non-Song wording cannot exclude a Greek expression.
4. `draft.noel_mark_translation_constraint_witnesses_v1`: individual canonical witnesses that support, limit, or contradict a claim. A separate source citation is mandatory for proof-quality review, and missing or opposing evidence remains visible.
5. `draft.noel_mark_state_transition_observations_v1`: attested source-token provenance plus manually checked participant, prior state, operation, resulting state and conditions. These are candidates until source reviewed; no automatic Greek-to-Hebrew state inference.
6. `draft.test_noel_mark_state_transition_v1(constraint_id, transition_id)`: deterministic, **read-only** test of whether a proposed state transition matches a source observation under its stated conditions and scope. Outcomes: compatible, counterexample candidate, unreviewed counterexample, different input, conditions not matched, or insufficient evidence. A mismatch never automatically forbids translation.
7. `draft.get_noel_mark_translation_reality_v1(source_token_id)`: secure private reality overlay for an existing source occurrence. It incorporates the existing private mark context reader, Song anchors, other Greek attestations and constraints.
8. `draft.get_noel_greek_to_hebrew_marks_v1(greek_lexeme_key)`: reverse LXX-to-Hebrew mark index; it never asserts functional equivalence.

All five tables are private and RLS-enabled. Neither readers nor tables are available to `anon` or `authenticated`.

## Constraint lifecycle

- `unassessed`: attested choice, no positive or negative functional verdict.
- `song_preferred`: Song attests a preferred Greek comparator; this is **not** an automatic claim that all other renderings are false.
- `compatible_candidate`: one testable state operation explains a Greek choice in a defined scope.
- `context_restricted`: observable participants, relation or prior state narrow where an interpretation can apply.
- `elimination_candidate`: a **proposed** contradiction with an actual canonical occurrence; opposing cases must be sought.
- `canon_excluded`: a reviewed, specifically scoped interpretation is demonstrably incompatible with canonical constraints. Requires founder/steward recorded decision, before/operation/after and explicit contradiction evidence. It never deletes attested Greek words or Hebrew occurrences.

The self-elimination engine should compare candidates using the **narrowest state-transition rule with testable predictions**. A candidate falls only if it contradicts an actual source transition while a narrower alternative survives, not merely because another translation sounds different. Mark identity itself is never eliminated.

## Current source census; do not promote provisional alignment

At initial review (Oct 15, 2026):
- 306,785 existing MT Hebrew token occurrences.
- Song: 1,255 source tokens, 804 distinct versioned consonantal NMIs.
- 287 Song NMIs with exactly one Greek indexed lexeme in clean direct 1:1 CATSS correspondences.
- 10 Song NMIs with multiple Greek lexemes directly attested in Song.
- 388 NMIs have non-direct phrase/variant associations requiring Song-local disambiguation.
- 119 have no represented CATSS token alignment in the inspected set.
- Of the 287 unambiguous direct anchors, 217 occur outside Song; 42,536 further Hebrew occurrences, of which 16,523 currently have clean 1:1 LXX token evidence.

These figures measure **alignment coverage and lexical choice**, not truth of a semantic equivalence. Do not manufacture anchors for the 507 outstanding Song identities. The former 132 disputed historical pool-label intersections do not set this vocabulary ontology.

## Rollout and validation

1. Preserve CATSS aligned phrase participants (1:many, many:1, many:many); carry the original member order, source/target cardinality, member role, review status and lexical head uncertainty. Never treat a Greek connective co-member as independently translating the Hebrew word.
2. Approve and merge this *public structural source only* by PR; no private founder words, interpretations, or source corpus in repository.
3. Run approved `Governed Migration Source Generation` with `release_lane=noel`, `fixture_path=none` and `validation_path=candidates/noel_song_translation_constraint_graph_v1/postconditions.sql`.
4. Apply the immutable generated migration and validation in the approved disposable **Production Schema Clone Validation** runner. Do not use a paid Supabase branch or unreviewed direct production DDL.
5. Merge only the validated generated migration, then use the protected manual `Production Database Release` workflow on main after explicit owner authorization.
6. Only after live verified release, execute `backfill_after_release_template.sql` with **each** `__BUCKET_0_TO_31__` replaced in order, using 32 short idempotent private write transactions. This populates **attested segment member choices**, including phrase candidates; they do not imply Greek lexical equivalence and never automatically produce translation permissions. Reconcile direct Song 287/10 and exact source/segment identities. Retry only failed buckets.
7. Use private reader to examine a Song-anchored token and reverse-map its Greek choices to other Hebrew marks. Record tested state-transition comparisons in constraint/evidence tables. **No automatic `canon_excluded` promotion.** For a reviewed exclusion, the guard requires a scoped steward decision and a source-checked, explicitly contradicted state transition.
8. Existing Noel/Titus/Atlas UI consumers remain unchanged until separately reviewed and authorized; this structural change grants no public access.

The existing 287 founder Reality Pool definitions, 196 decisions, 278 aliases and earlier mark registry must remain byte-identical throughout structural deployment and backfill.