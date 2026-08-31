-- Atlas Person Goal -> Rhythm performance hygiene v1
--
-- Performance-only follow-up to the Goal/Rhythm authority bridge. Adds direct
-- indexes for newly introduced foreign-key lookup paths that are not already
-- covered by a leading index column, and evaluates auth.uid() once per query in
-- the two signed-in self-read policies. No truth, authority, or write behavior
-- changes.

begin;

create index if not exists person_goal_rhythm_bindings_goal_definition_idx
  on atlas.person_goal_rhythm_bindings(goal_definition_id);
create index if not exists person_goal_rhythm_bindings_plan_evidence_idx
  on atlas.person_goal_rhythm_bindings(plan_evidence_id);
create index if not exists person_goal_rhythm_bindings_retired_by_plan_claim_idx
  on atlas.person_goal_rhythm_bindings(retired_by_plan_claim_id);

create index if not exists person_rhythm_opportunities_rhythm_definition_idx
  on atlas.person_rhythm_opportunities(rhythm_definition_id);
create index if not exists person_rhythm_opportunities_source_plan_claim_idx
  on atlas.person_rhythm_opportunities(source_plan_claim_id);
create index if not exists person_rhythm_opportunities_source_plan_evidence_idx
  on atlas.person_rhythm_opportunities(source_plan_evidence_id);

drop policy if exists person_goal_rhythm_bindings_self_read
  on atlas.person_goal_rhythm_bindings;
create policy person_goal_rhythm_bindings_self_read
on atlas.person_goal_rhythm_bindings for select to authenticated
using (owner_user_id=(select auth.uid()));

drop policy if exists person_rhythm_opportunities_self_read
  on atlas.person_rhythm_opportunities;
create policy person_rhythm_opportunities_self_read
on atlas.person_rhythm_opportunities for select to authenticated
using (owner_user_id=(select auth.uid()));

commit;
