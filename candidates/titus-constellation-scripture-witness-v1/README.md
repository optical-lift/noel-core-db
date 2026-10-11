# Titus Constellation — Scripture chapter witness candidate

This is the next **read-only, private** piece of the full-sky + Scripture-connected reading product direction. It allows the existing Constellation UI to request real chapter witness tokens without shipping a static Bible dump or copying Noel founder research to a public repository.

**Exact source inputs:** `draft.token_occurrences` is the existing CrossWire KJV tagged English corpus; `draft.ot_canonical_tokens_stage` is the existing MT Hebrew token spine. English and Hebrew have distinct token identities and ordering. **Do not equate KJV Strong's numbers with direct MT word alignment.** Only `draft.noel_reality_token_anchors` rows with `mt_noel_current` and an approved source-spine verification state join to an active pool by the **exact MT source_token_id**.

The response includes every available English and Hebrew token in a requested chapter, each with witness provenance; no inference from lexical similarity. Where the chapter has no anchor, it remains unlit. A word with multiple verified pool links retains them. The function does not read or expose Noel definition/note bodies; the separate private constellation snapshot still controls what node descriptions exist.

**Boundary:** `SECURITY INVOKER`, service-role EXECUTE only. Atlas person-bound viewer authorization remains a separate prerequisite to any external/private preview and this migration itself grants no users access. No browser secrets, no automatic publication, no synthetic fixture. Build UI preserves original full-sky home and does not invent semantic edges.

**Proof passage:** Psalm 147:2–3 contains verified MT token anchors to Healing, Repair, Restoration and the damaged/displaced before-state family (as observed in the live source as of October 10, 2026). Psalm 23 is **not** described as mapped: its Reality Pool anchors are currently absent. A source-only candidate may be tested in a disposable schema clone; production requires the canonical Shared source generator, exact validation, reviewed merge and protected manual release. This PR does not deploy the function.
