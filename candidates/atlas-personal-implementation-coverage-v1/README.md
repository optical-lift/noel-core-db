# Personal implementation coverage — Atlas candidate only

**Scope:** PMD-027 privacy-minimized, read-only evidence of Personal Atlas adoption in the existing professional Implementation Workbench. This does not establish real-world facts, grant the practitioner private access, create a source or Ledger, complete a case, or write any data.

The candidate uses a **separate v1 read RPC** rather than changing `implementation_case_self_api_v2` or its paid institutional branch. A verified practitioner can inspect case-level milestones for a real `personal_atlas` case: canonical Auth-to-Person/Principal/native Atlas binding; active Home household; existence (not content) of Bookplate evidence, first-day session state, confirmed discovery evidence, and a narrow dated-task entry receipt.

The result explicitly returns `not_assessed` for provider sources, Ledger scope and domain promotion, and `not_evaluated` for completion. It returns **no private text, household members, answers, task titles, source accounts, organizations, providers, amounts, Ledger names, source refs, or identifiable Person/Auth UUIDs**. In particular a missing task entry does not mean the person has not used Atlas, and Foundry evidence is not promoted reality.

Authorization is checked inside the SECURITY DEFINER function using the same separately authenticated practitioner gate as the existing Workbench. An ordinary Personal Atlas login must receive `practitioner_authority_required`. An unknown/nonpersonal case must return `personal_case_not_found`. Revoke direct function access and expose only the narrow public wrapper to `authenticated`.

## Review/release order

1. Review the source against the current case-origin and auth-binding contracts and privacy limits; do not include real-user fixtures in Git.
2. Merge this **candidate packet** through review, then request canonical `atlas_` migration generation by owner issue from the exact merged candidate commit. Do not hand-invent a production migration filename.
3. Exercise disposable production-shaped clone cases: valid practitioner/personal case, ordinary user denied, unknown case denied, paid institutional case denied, no private fields, valid evidence state, zero-evidence state, and subject separation.
4. Review generated migration; release through the protected canonical DB lane. **No direct production DDL**.
5. Only after DB release, release the dependent Atlas app PR, then have a human verify the visible case coverage without any private data crossing the practitioner boundary.

This is intentionally an intermediate coverage view. A **separate Principal-authenticated self projection** is required before presenting actual existing Ledger names and other personal contents to the person in their notebook.
