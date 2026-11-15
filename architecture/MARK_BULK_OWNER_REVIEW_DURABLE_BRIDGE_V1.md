# Mark bulk review owner-custody bridge — reviewed design proposal

Date: 2026-11-14. Status: SOURCE PROPOSAL ONLY; no database migration applied.
Target: shared Noel Supabase physical project zirqkouammpwxlqfbsvf.
Owner: Noel owns private mark evidence; Write Now may request access only through explicit scoped owner bridge.

## User goal and existing evidence

The original source is 1QIsa(a), 29696 x 5013px, original JPEG SHA-256
8f64008c1f5310836f0fca8f42f395158641b3052921f92fcb2f213315eea4b0.
A bulk extraction generated 13,860 connected dark-region proposals, 9,908 grouped into 96 unreviewed visual clusters with 3,346 unreviewed component-joining hypotheses. The groups are not accepted ancient signs, complete ink boundaries, Hebrew/Greek letters, Song meanings, or training labels.

Write Now PR #72 now proposes a native bulk-review lens using the existing FamilyCheatSheet, SourceContextInspector and SourceCropCache, source-native boxes, family assignments, rejections/damage, group/batch approval, import/export of owner review JSON, and query-time family-conditioned retrieval. The browser must eventually sync evidence to Noel so the owner and authorized AI operator can reason over it across devices.

## New database objects to design (not deployed)

1. Private mark.photo_component_catalogues:
   catalogue_id, private capture_id referencing mark.captures, original source SHA,
   native dimensions, algorithm version, immutable catalogue digest, rights and source provenance,
   verification/admission status. Multiple model/capture runs of the same photograph do not establish independent witnesses.
2. Private mark.photo_component_proposals:
   unique (catalogue_id, source_component_id); immutable native original rectangle,
   original algorithm cohort/visual bin, candidate kind, source feature version,
   ink-boundary-approved=false, training-authorized=false. These are not automatically inserted
   into canonical mark.instances.
3. Private mark.photo_review_events:
   server-generated event_id, catalogue_id, owner actor bound to a genuinely verified
   signed session, server receipt time, idempotency key, sequence, action ASSIGN|UNDO,
   event lineage, original source SHA, reversal reference. Append-only; deny UPDATE and DELETE.
4. Private mark.photo_review_event_decisions:
   event_id, source_component_id FK, immutable original source location FK,
   owner-reviewed new rectangle, owner visual verdict (VISUAL_FAMILY, NOT_THIS_FAMILY,
   CREASE, DAMAGE, FRAGMENT, POSSIBLE_JOIN, UNKNOWN), family tag when applicable,
   optional note, authority as OWNER_ADJUSTED_REVIEW_RECTANGLE_NOT_INK_MASK,
   no verified ink mask, no training label, no canonical linguistic sign, no semantic function.
   Up to 600 individual decisions per atomic batch.
5. Private mark.photo_retrieval_runs:
   frozen retrieval algorithm/parameters, family query, reviewed positives and
   family-scoped negatives, proposal candidates and scores, field/physical-source
   holdouts, abstentions. Never automatically creates review events or training labels.

The read model is computed from append-only ASSIGN/UNDO decisions without overwriting earlier
reviews. Original proposal box, corrected owner box, actual mask, visual family and
interpretive claim must be independent fields with separate authorities.

## Authorization and bridge

- Existing mark schema has private, RLS-guarded custody. Keep direct privileges absent
  for public, anon, authenticated, and generic service_role application access.
- Expose only a separately reviewed narrowly scoped owner-authenticated
  WNPH API/server bridge. No service-role bypass, client secrets or direct
  browser reads of mark. Verify signed identity and live source-scoped owner rights.
- A source SHA-256 typed into JSON is not authorization. Revalidate every original
  source proposal, native dimensions, owner rectangle, event type, source owner,
  family tag and event digest on the server. Reject forged actor, training flag,
  ink masks and semantics; do not trust browser input.
- Pagination and source catalogue hash are required for 13,860 proposed regions;
  metadata may cross the bridge only with owner authorization, and original or
  derivative photo pixels remain under separately rights-cleared custody.
- Read-only query surface first; independently signed negative-access tests,
  then a separately authorized append-only write surface. A migration or source
  merge alone never authorizes production deployment.

## Learning from classifications

The first learning lane is explicit non-neural exemplar-based retrieval.
Owner-corrected source crops yield fresh physical descriptors at new native
coordinates, verified against the original photo. Positive family examples and
explicit family-scoped negatives re-rank proposals and identify abstentions.
Machine cluster IDs (B-008 etc.) remain temporary discovery bins and NEVER
become owner-authorized family identities by default. Other-family labels,
creases, partial marks, damage and unknown remain distinct.
A frozen region/source holdout and false-match/missed-match audit are required
before qualification. Any neural-weight training or continuously altered model
requires separate promotion under Song Ontology GOVERNANCE section 17.

## Signed negative tests required for production

- Valid owner signed session can read only own source; outsider signed user,
  anonymous, stale/revoked session, fabricated identity and service-role
  transport lacking owner context receive no private rows or writes.
- Deny a forged SHA, altered original rectangle, out-of-bounds owner box,
  unknown catalogue, wrong physical witness, unapproved family, fabricated
  full ink mask, semantic function and training authorization.
- Owner batch with 600 decisions is atomic and replayable; 601 is rejected.
  Concurrent revisions and duplicate idempotency keys cannot silently overwrite.
  Undo appends a reversal rather than erasing earlier owner testimony.
- Original mark.captures / regions / instances are unchanged after catalogue
  ingestion; candidate observations remain separate from canonical mark.
- Prove no original pixels, private owner decisions or founder observations
  appear in Git, CI logs, public migrations, browser bundle or unauthorized API.
- Verify read-only retrieval never grants machine authority to confirm an owner family.

## Required release sequence

This repository owns all shared database migrations. Implement private mark
DDL via the governed Noel core migration lane, and any cross-domain identity
bridge via a separately reviewed shared or WNPH API lane. Generate migration
filenames with repository tooling, validate on a disposable full-schema clone,
run RLS/negative signed tests, and require explicit owner approval for the
exact protected production release version and target. No direct execute_sql,
no automatic apply_migration, no schema permission broadening, no PR merge,
and no production DDL are authorized by this proposal.
