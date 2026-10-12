# Atlas first-use Foundry without mandatory Index (2026-10-12)

The existing first-day status requires an orientation-v4 Index selection, whereas the new Foundry writes a human Field/Position/Scale orientation-v3. Deleting the Index UI alone does not satisfy this old gate. This candidate changes `entranceCaptured` and `shouldAutoOpen` to depend on **Bookplate plus any captured human orientation**, while leaving `indexCaptured` explicitly independent and truthful.

The existing ranked question-selector formerly filters first-day questions only when v4 Index is captured. This candidate uses the human's v3 world domain to restrict the first encounter when no intentional Index exists. A v4 Index remains first if explicitly present. The orientation reader now selects the newest evidence event by occurrence rather than always preferring v4 even when an explicit v3 choice is newer. This is not a model-driven question generator.

**Boundary:** A selected Field determines scope and question eligibility; it does not assert facts about relationships not yet established. The notebook can later maintain an Index from discovered facts or human choices. No auto-synthesized Index-v4 event is created as an onboarding shortcut.

Unexecuted, source-first SQL candidate. Requires protected production-schema clone tests with realistic orientation-v3, old Index-v4, and absent Index scenarios, and full first-user acceptance before any migration release. Do not apply against live production through direct SQL.

**Review correction:** A prior v4 Index selection may exist even after newer v3 Field orientation. The first-day question filter must use v4 only when v4 is *also* the latest human orientation. If newer v3 is active, route from v3 worldDomains, not old v4 categories. The contract validator now rejects stale-Index precedence.
