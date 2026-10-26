# Foundry human source-custody review — Stage 3 source candidate

**SOURCE-ONLY. NOT in production, not yet clone validated, not an AI access grant.**

The current Foundry workspace registry has a strong `reviewed` gate that Atlas's delegated-agent evaluator checks. This build intentionally **never marks that registry as reviewed**. That prevents the human review of a document claim from silently authorizing an AI carrier or opening broad Foundry operations.

For each pending workspace, an authenticated owner may submit an **exact source-scope claim** naming:
- stable references to source documents or artifacts (not their interpreted contents);
- one basis category (`first_party`, `public_source`, `subject_authorization`, `custodian_authorization`);
- a written claimed provenance/authority basis, in the owner's words;
- allowed **human** actions only: `catalog`, `preserve`, `transcribe`, `analyze`;
- a different existing active Atlas Principal who will independently review.

Only that named reviewer, in a real active nonanonymous GoTrue session, may approve or reject with a written independent basis. The owner or reviewer may revoke pending/approved cases, with a reason. All transitions are append-only Foundry event evidence plus current private case state, in one transaction, with immutable source IDs and stable request IDs.

There is no new Person, Ledger, employee seat, login, carrier, source-provider credential, SQL CRUD surface or direct private table grant. No connected source is fetched, files uploaded or AI testimony interpreted by this build. Human approval proves **that a review decision happened**, *not* that the external subject actually granted consent, a document is authentic, or an AI now possesses access. The reviewer must verify the original authorization and provenance outside of this system; the evidentiary record preserves their accountable claim.

Private functions: `atlas.foundry_current_signed_principal_v1`, `atlas.request_foundry_source_custody_review_self_api_v1`, `atlas.inspect_foundry_source_custody_review_self_api_v1`, `atlas.decide_foundry_source_custody_review_self_api_v1`, `atlas.revoke_foundry_source_custody_review_self_api_v1`. The four public RPCs are thin **SECURITY INVOKER** wrappers with authenticated-only grants.

The review target uses an existing Atlas Principal ID, not a separate role/seat type. A connected-Person selector in Atlas should supply that ID; this source candidate cannot invent who is authorized to review.

## Proof and release gates

Run this SQL after the successfully tested signed Foundry Gate 2 schema in the existing free GitHub local production-schema clone. Require:
- source/ACL assertions; no new public SECURITY DEFINER; private RLS and no direct table grants;
- two real *different* signed GoTrue human sessions, owner vs reviewer and outsider;
- no-Principal and anonymous rejection, session revocation, tampered metadata/target denial;
- source-scoped request idempotence, reviewer-only approval, exact preserve of basis, concurrent attempts;
- owner/reviewer revocation, read isolation, event order and historical event immutability;
- `workspace_authority_registry_v1.custody_review_state` stays `pending` on both approval and revocation;
- no new `atlas.agent_command_definitions` row, no delegated AI grants, no canonical Atlas writes.

The `roll-back` test in the same candidate's validation suite includes synthetic provenance only. Production is read-only for schema snapshot and retains 93 historical events / five snapshots as previously audited.

**Do not deploy based only on passing structural tests.** Signed transport and two-person authority must pass. Subject consent, permission from other organizations and legal eligibility are not inferred from a review case.
